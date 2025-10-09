import Foundation
import Combine
import StoreKit

enum PurchaseState {
    case unknown
    case notPurchased
    case purchased(receiptId: String)
}

enum PurchaseError: LocalizedError {
    case purchaseFailed(String)
    case restoreFailed(String)
    case receiptNotFound
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .purchaseFailed(let message):
            return "Purchase failed: \(message)"
        case .restoreFailed(let message):
            return "Restore failed: \(message)"
        case .receiptNotFound:
            return "No valid purchase receipt found"
        case .networkError:
            return "Network error. Please check your connection."
        }
    }
}

@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    @Published private(set) var purchaseState: PurchaseState = .unknown
    @Published private(set) var currentReceiptId: String?
    @Published private(set) var isLoading = false
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var availablePromotions: [String: Product.SubscriptionOffer] = [:]
    
    private let logger = DebugLogger.shared
    private let keychainManager = KeychainManager.shared
    private let receiptKey = "purchase_receipt_id"
    private var updateListenerTask: Task<Void, Never>?
    
    private init() {
        Task {
            await checkPurchaseStatus()
        }
        
        // Start listening for transaction updates
        updateListenerTask = Task {
            await observeTransactionUpdates()
        }
    }
    
    // MARK: - Public Methods
    
    func checkPurchaseStatus() async {
        logger.log("🛒 Checking purchase status", level: .info)
        
        // First check if we have a stored receipt ID
        if let storedReceiptId = keychainManager.retrieve(String.self, forKey: receiptKey) {
            await MainActor.run {
                self.purchaseState = .purchased(receiptId: storedReceiptId)
                self.currentReceiptId = storedReceiptId
            }
            logger.log("✅ Found stored receipt: \(storedReceiptId.prefix(8))...", level: .info)
            return
        }
        
        // Check for valid StoreKit transactions
        await checkForValidTransactions()
    }
    
    func restorePurchases() async throws {
        logger.log("🔄 Restoring purchases", level: .info)
        await MainActor.run { isLoading = true }
        
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        do {
            try await AppStore.sync()
            await checkForValidTransactions()
            
            if case .purchased = purchaseState {
                logger.log("✅ Purchase restoration successful", level: .info)
            } else {
                throw PurchaseError.receiptNotFound
            }
        } catch {
            logger.logError(error, context: "Purchase restoration failed")
            throw PurchaseError.restoreFailed(error.localizedDescription)
        }
    }
    
    
    func purchase(productId: String) async throws {
        logger.log("💳 Starting real StoreKit purchase for product: \(productId)", level: .info)
        await MainActor.run { isLoading = true }
        
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // Fetch products from App Store
        let products = try await Product.products(for: [productId])
        guard let product = products.first else {
            logger.log("❌ Product not found: \(productId)", level: .error)
            throw PurchaseError.purchaseFailed("Product not found")
        }
        
        // Initiate purchase
        // Note: Promotional offers are automatically applied by StoreKit based on eligibility
        // The promotional pricing is handled at the display level, not the purchase level
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            // Verify the transaction
            switch verification {
            case .verified(let transaction):
                // Use the original transaction ID as our stable user identifier
                let receiptId = String(transaction.originalID)
                
                // Store for future use
                keychainManager.store(receiptId, forKey: receiptKey)
                
                await MainActor.run {
                    self.purchaseState = .purchased(receiptId: receiptId)
                    self.currentReceiptId = receiptId
                }
                
                // Always finish transactions
                await transaction.finish()
                
                #if DEBUG
                logger.log("✅ Purchase successful: \(receiptId.prefix(8))...", level: .info)
                #else
                logger.log("✅ Purchase successful", level: .info)
                #endif
                
            case .unverified(let transaction, let error):
                // Failed verification
                await transaction.finish()
                logger.logError(error, context: "Purchase verification failed")
                throw PurchaseError.purchaseFailed("Verification failed")
            }
            
        case .userCancelled:
            logger.log("👤 User cancelled purchase", level: .info)
            throw PurchaseError.purchaseFailed("Purchase cancelled")
            
        case .pending:
            logger.log("⏳ Purchase pending (parental approval, etc.)", level: .info)
            throw PurchaseError.purchaseFailed("Purchase pending approval")
            
        @unknown default:
            logger.log("❌ Unknown purchase result", level: .error)
            throw PurchaseError.purchaseFailed("Unknown error")
        }
    }
    
    // MARK: - Computed Properties
    
    var isPurchased: Bool {
        if case .purchased = purchaseState {
            return true
        }
        return false
    }
    
    var userIdentifier: String? {
        return currentReceiptId
    }
    
    // MARK: - Private Methods
    
    private func checkForValidTransactions() async {
        // Check for current entitlements
        for await transaction in Transaction.currentEntitlements {
            guard case .verified(let validTransaction) = transaction else {
                continue
            }
            
            // Use the original transaction ID as our stable user identifier
            let receiptId = String(validTransaction.originalID)
            
            // Store for future use
            keychainManager.store(receiptId, forKey: receiptKey)
            
            await MainActor.run {
                self.purchaseState = .purchased(receiptId: receiptId)
                self.currentReceiptId = receiptId
            }
            
            logger.log("✅ Valid transaction found: \(receiptId.prefix(8))...", level: .info)
            return
        }
        
        // No valid transactions found
        await MainActor.run {
            self.purchaseState = .notPurchased
            self.currentReceiptId = nil
        }
        logger.log("🚫 No valid purchases found", level: .info)
    }
    
    func fetchProductsForDisplay() async throws {
        logger.log("🛍️ Fetching products for display", level: .info)
        await MainActor.run { isLoadingProducts = true }
        
        defer {
            Task { @MainActor in
                isLoadingProducts = false
            }
        }
        
        let productIds = ["daystart_annual_subscription", "daystart_monthly_subscription"]
        let products = try await Product.products(for: productIds)
        
        // Check for promotional offers on each product
        var promotions: [String: Product.SubscriptionOffer] = [:]
        for product in products {
            if let offers = await checkEligiblePromotionalOffers(for: product),
               let bestOffer = offers.first {
                promotions[product.id] = bestOffer
                logger.log("🎁 Found promotional offer for \(product.id): \(bestOffer.id ?? "unknown")", level: .info)
            }
        }
        
        await MainActor.run {
            self.availableProducts = products.sorted { product1, product2 in
                // Sort by price descending (annual first)
                product1.price > product2.price
            }
            self.availablePromotions = promotions
        }
        
        logger.log("✅ Fetched \(products.count) products with \(promotions.count) promotional offers", level: .info)
    }
    
    func checkEligiblePromotionalOffers(for product: Product) async -> [Product.SubscriptionOffer]? {
        guard let subscription = product.subscription else { return nil }
        
        // Get all promotional offers (not introductory offers)
        let promotionalOffers = subscription.promotionalOffers
        
        // In a real app, you might check eligibility based on user status
        // For now, return all available promotional offers
        if !promotionalOffers.isEmpty {
            logger.log("🔍 Found \(promotionalOffers.count) promotional offers for \(product.id)", level: .info)
        }
        
        return promotionalOffers.isEmpty ? nil : promotionalOffers
    }
    
    func getPromotionalPrice(for product: Product) -> (original: Decimal, promotional: Decimal, savingsPercent: Int)? {
        guard let offer = availablePromotions[product.id],
              let subscription = product.subscription else { return nil }
        
        let originalPrice = product.price
        
        // Calculate promotional price based on offer type
        let promotionalPrice: Decimal
        switch offer.paymentMode {
        case .payAsYouGo:
            // Discounted price for the offer period
            promotionalPrice = offer.price ?? originalPrice
        case .payUpFront:
            // One-time discounted payment
            promotionalPrice = offer.price ?? originalPrice
        case .freeTrial:
            // Free trial (already handled as intro offer)
            return nil
        default:
            return nil
        }
        
        // Calculate savings percentage
        let savings = originalPrice - promotionalPrice
        let savingsPercent = Int(((savings / originalPrice) * 100) as NSDecimalNumber)
        
        return (original: originalPrice, promotional: promotionalPrice, savingsPercent: savingsPercent)
    }
    
    private func clearStoredReceipt() {
        keychainManager.delete(forKey: receiptKey)
        currentReceiptId = nil
        purchaseState = .notPurchased
        logger.log("🧹 Cleared stored receipt", level: .info)
    }
    
    private func observeTransactionUpdates() async {
        logger.log("🔄 Starting transaction update observer", level: .info)
        
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else {
                continue
            }
            
            logger.log("📦 Processing transaction update: \(transaction.productID)", level: .info)
            
            // Use the original transaction ID as our stable user identifier
            let receiptId = String(transaction.originalID)
            
            // Store for future use
            keychainManager.store(receiptId, forKey: receiptKey)
            
            await MainActor.run {
                self.purchaseState = .purchased(receiptId: receiptId)
                self.currentReceiptId = receiptId
            }
            
            // Always finish transactions
            await transaction.finish()
            
            logger.log("✅ Transaction processed: \(receiptId.prefix(8))...", level: .info)
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
}