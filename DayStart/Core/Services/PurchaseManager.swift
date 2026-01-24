import Foundation
import Combine
import StoreKit
import SwiftUI

// MARK: - Purchase Types

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
    case productNotFound
    case keychainStorageFailed(String)

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
        case .productNotFound:
            return "Product not found"
        case .keychainStorageFailed(let message):
            return "Failed to save purchase: \(message)"
        }
    }
}

// MARK: - StoreKit Purchase Manager

/// StoreKit 2 based implementation of PurchaseManager
/// Provides subscription management without external dependencies
@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    // MARK: - Published Properties
    @Published private(set) var purchaseState: PurchaseState = .unknown
    @Published private(set) var currentReceiptId: String?
    @Published private(set) var isLoading = false
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPremium: Bool = false
    
    private let logger = DebugLogger.shared
    private let keychainManager = KeychainManager.shared
    private let receiptKey = "purchase_receipt_id"
    private let receiptUserDefaultsKey = "purchase_receipt_id_backup"
    private let anonymousUserIdKey = "anonymous_user_id"
    private var updateListenerTask: Task<Void, Never>?
    
    // Product IDs
    private let productIds = [
        "daystart_weekly_subscription",
        "daystart_monthly_subscription",
        "daystart_annual_subscription"
    ]
    
    private init() {
        Task {
            await checkPurchaseStatus()
            await fetchProducts()
        }
        
        // Listen for transaction updates
        updateListenerTask = listenForTransactions()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Transaction Listener
    
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            // Listen for transaction updates
            for await result in Transaction.updates {
                await self.handle(transactionResult: result)
            }
        }
    }
    
    @MainActor
    private func handle(transactionResult result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else {
            logger.log("⚠️ Unverified transaction received", level: .warning)
            return
        }

        do {
            // Update purchase state (includes storage with retry logic)
            try await updatePurchaseState(from: transaction)

            // ONLY finish transaction after successful storage
            await transaction.finish()
            logger.log("✅ Transaction finished successfully: \(transaction.id)", level: .info)

        } catch {
            // CRITICAL: Do NOT finish transaction if storage failed
            logger.log("🚨 CRITICAL: Not finishing transaction \(transaction.id) due to storage failure. Will retry on next app launch.", level: .error)
            logger.logError(error, context: "Transaction listener storage failure")

            // StoreKit will redeliver this transaction on next app launch
            // This is MUCH better than losing the user's purchase
        }
    }
    
    // MARK: - Public Methods
    
    func checkPurchaseStatus() async {
        logger.log("🛒 Checking purchase status", level: .info)

        // Use dual storage retrieval (Keychain first, UserDefaults fallback)
        if let storedReceiptId = retrieveReceiptId() {
            self.purchaseState = .purchased(receiptId: storedReceiptId)
            self.currentReceiptId = storedReceiptId
            self.isPremium = true
            logger.log("✅ Found stored receipt: \(storedReceiptId.prefix(8))...", level: .info)
        }

        // Always check for valid StoreKit transactions
        await checkForValidTransactions()
    }
    
    func fetchProducts() async {
        guard !isLoadingProducts else { return }
        
        isLoadingProducts = true
        logger.log("📦 Fetching products: \(productIds)", level: .info)
        
        do {
            let products = try await Product.products(for: productIds)
            self.availableProducts = products.sorted { $0.price < $1.price }
            logger.log("✅ Fetched \(products.count) products", level: .info)
        } catch {
            logger.logError(error, context: "Failed to fetch products")
        }
        
        isLoadingProducts = false
    }
    
    func fetchProductsForDisplay() async throws {
        if availableProducts.isEmpty {
            await fetchProducts()
        }
    }
    
    func purchase(productId: String) async throws {
        logger.log("💳 Starting purchase for product: \(productId)", level: .info)
        
        guard let product = availableProducts.first(where: { $0.id == productId }) else {
            throw PurchaseError.productNotFound
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    logger.log("✅ Purchase verified: \(transaction.id)", level: .info)

                    do {
                        try await updatePurchaseState(from: transaction)
                        await transaction.finish()
                        logger.log("✅ Purchase completed and transaction finished", level: .info)

                    } catch {
                        // If storage fails, throw error to UI but DON'T finish transaction
                        logger.log("🚨 Purchase storage failed - transaction not finished", level: .error)

                        if let purchaseError = error as? PurchaseError {
                            throw purchaseError
                        } else if let keychainError = error as? KeychainManager.KeychainError {
                            throw PurchaseError.keychainStorageFailed(keychainError.localizedDescription)
                        } else {
                            throw PurchaseError.keychainStorageFailed("Failed to save purchase. Please try again.")
                        }
                    }

                case .unverified(_, let error):
                    logger.logError(error, context: "Purchase verification failed")
                    throw PurchaseError.purchaseFailed("Verification failed")
                }

            case .userCancelled:
                logger.log("🚫 Purchase cancelled by user", level: .info)
                throw PurchaseError.purchaseFailed("Purchase was cancelled")
                
            case .pending:
                logger.log("⏳ Purchase pending", level: .info)
                throw PurchaseError.purchaseFailed("Purchase is pending. Please check back later.")
                
            @unknown default:
                throw PurchaseError.purchaseFailed("Unknown error occurred")
            }
        } catch let error as PurchaseError {
            throw error
        } catch {
            throw PurchaseError.purchaseFailed(error.localizedDescription)
        }
    }
    
    func restorePurchases() async throws {
        logger.log("🔄 Restoring purchases", level: .info)
        isLoading = true
        
        defer { isLoading = false }
        
        do {
            try await AppStore.sync()
            await checkForValidTransactions()
            
            if isPremium {
                logger.log("✅ Purchase restoration successful", level: .info)
            } else {
                throw PurchaseError.receiptNotFound
            }
        } catch {
            logger.logError(error, context: "Purchase restoration failed")
            throw PurchaseError.restoreFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Helper Methods
    
    func getTrialText(for product: Product) -> String? {
        guard let subscription = product.subscription,
              let introOffer = subscription.introductoryOffer else {
            return nil
        }
        
        if case .freeTrial = introOffer.paymentMode {
            let period = introOffer.period
            return "\(period.value) Day Free Trial"
        }
        
        return nil
    }
    
    func getPromotionalPrice(for product: Product) -> (Decimal, Int)? {
        guard let subscription = product.subscription,
              let introOffer = subscription.introductoryOffer,
              introOffer.paymentMode == .payAsYouGo || introOffer.paymentMode == .payUpFront else {
            return nil
        }
        
        let priceDouble = Double(truncating: product.price as NSDecimalNumber)
        let introDouble = Double(truncating: introOffer.price as NSDecimalNumber)
        let savingsPercent = Int(((priceDouble - introDouble) / priceDouble) * 100)
        return (introOffer.price, savingsPercent)
    }
    
    func getSavingsText(annual: Product?, monthly: Product?) -> String? {
        guard let annualProduct = annual,
              let monthlyProduct = monthly else { return nil }
        
        let monthlyDouble = Double(truncating: monthlyProduct.price as NSDecimalNumber)
        let annualDouble = Double(truncating: annualProduct.price as NSDecimalNumber)
        let monthlyTotal = monthlyDouble * 12
        let savings = monthlyTotal - annualDouble
        let savingsPercent = Int((savings / monthlyTotal) * 100)
        
        if savingsPercent > 0 {
            return "Save \(savingsPercent)%"
        }
        return nil
    }
    
    func getWeeklySavings(for product: Product, weeklyProduct: Product?) -> (percentage: Int, color: Color)? {
        guard let weekly = weeklyProduct else { return nil }
        
        let weeklyDouble = Double(truncating: weekly.price as NSDecimalNumber)
        let productDouble = Double(truncating: product.price as NSDecimalNumber)
        
        // Calculate annual cost for comparison
        let weeklyAnnual = weeklyDouble * 52
        let productAnnual: Double
        
        // Determine product annual cost based on subscription period
        if let subscription = product.subscription {
            switch subscription.subscriptionPeriod.unit {
            case .week:
                productAnnual = productDouble * 52
            case .month:
                productAnnual = productDouble * 12
            case .year:
                productAnnual = productDouble
            default:
                return nil
            }
        } else {
            return nil
        }
        
        // Don't show badge if product is more expensive than weekly
        guard productAnnual < weeklyAnnual else { return nil }
        
        let savings = weeklyAnnual - productAnnual
        let savingsPercent = Int((savings / weeklyAnnual) * 100)
        
        // Dynamic green color based on savings percentage
        let color: Color
        if savingsPercent >= 50 {
            color = Color.green // Bright green for 50%+ savings
        } else if savingsPercent >= 30 {
            color = Color.green.opacity(0.8) // Medium green for 30-49% savings
        } else {
            color = Color.green.opacity(0.6) // Light green for under 30% savings
        }
        
        return (percentage: savingsPercent, color: color)
    }
    
    // MARK: - Computed Properties

    /// Anonymous user ID - generated once on first app launch and persists forever
    /// This becomes the permanent user identifier even after purchase (receipt tracked separately)
    private var anonymousUserId: String {
        // Check if we already have one
        if let existingId = UserDefaults.standard.string(forKey: anonymousUserIdKey) {
            return existingId
        }

        // Generate new anonymous ID (format: anon_UUID)
        let newId = "anon_\(UUID().uuidString)"
        UserDefaults.standard.set(newId, forKey: anonymousUserIdKey)
        UserDefaults.standard.synchronize()

        logger.log("🆔 Generated new anonymous user ID: \(newId.prefix(20))...", level: .info)
        return newId
    }

    /// Returns the user identifier for API calls
    /// IMPORTANT: Always returns anonymous ID (permanent), even after purchase
    /// Receipt ID is tracked separately in currentReceiptId for premium verification
    var userIdentifier: String? {
        return anonymousUserId
    }
    
    // MARK: - Dual Storage Methods

    /// Store receipt ID with retry logic and dual storage (Keychain primary, UserDefaults backup)
    /// - Parameter receiptId: The receipt ID to store
    /// - Parameter maxAttempts: Maximum retry attempts (default 3)
    /// - Throws: PurchaseError.keychainStorageFailed if BOTH storage methods fail
    private func storeReceiptIdWithRetry(_ receiptId: String, maxAttempts: Int = 3) async throws {
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                // Try Keychain first (primary storage)
                try keychainManager.storeWithError(receiptId, forKey: receiptKey)

                // Also store in UserDefaults as backup
                UserDefaults.standard.set(receiptId, forKey: receiptUserDefaultsKey)
                UserDefaults.standard.synchronize()

                logger.log("✅ Receipt stored successfully (attempt \(attempt + 1)): \(receiptId.prefix(8))...", level: .info)
                return // Success!

            } catch let error as KeychainManager.KeychainError {
                lastError = error

                // Log the specific error
                logger.log("⚠️ Keychain storage attempt \(attempt + 1) failed: \(error.localizedDescription)", level: .warning)

                if attempt == maxAttempts - 1 {
                    // Last attempt failed, try UserDefaults only as final fallback
                    logger.log("🚨 All Keychain attempts failed, using UserDefaults-only storage", level: .error)
                    UserDefaults.standard.set(receiptId, forKey: receiptUserDefaultsKey)
                    UserDefaults.standard.synchronize()

                    // REFINEMENT: Don't throw if UserDefaults succeeds - we have persistent storage
                    logger.log("✅ Receipt stored in UserDefaults backup (Keychain unavailable): \(receiptId.prefix(8))...", level: .warning)
                    return // Success via fallback
                }

                // Exponential backoff: 0.5s, 1.5s, 3.5s
                let delay = 0.5 * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            } catch {
                lastError = error
                logger.logError(error, context: "Unexpected error storing receipt (attempt \(attempt + 1))")

                // For unknown errors, still retry
                if attempt < maxAttempts - 1 {
                    let delay = 0.5 * pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // If we get here, all attempts failed
        throw lastError ?? PurchaseError.keychainStorageFailed("Failed to store receipt after \(maxAttempts) attempts")
    }

    /// Retrieve receipt ID from dual storage (Keychain first, UserDefaults fallback)
    /// - Returns: The receipt ID if found in either storage, nil otherwise
    private func retrieveReceiptId() -> String? {
        // Try Keychain first
        if let receiptId = keychainManager.retrieve(String.self, forKey: receiptKey) {
            logger.log("📦 Retrieved receipt from Keychain: \(receiptId.prefix(8))...", level: .debug)
            return receiptId
        }

        // Fallback to UserDefaults
        if let receiptId = UserDefaults.standard.string(forKey: receiptUserDefaultsKey) {
            logger.log("📦 Retrieved receipt from UserDefaults backup: \(receiptId.prefix(8))...", level: .info)

            // Try to restore to Keychain in background
            Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    try await self.storeReceiptIdWithRetry(receiptId, maxAttempts: 1)
                    await MainActor.run {
                        self.logger.log("✅ Restored receipt to Keychain from UserDefaults", level: .info)
                    }
                } catch {
                    // Ignore errors - UserDefaults is working as fallback
                }
            }

            return receiptId
        }

        return nil
    }

    // MARK: - Private Methods

    private func checkForValidTransactions() async {
        // Check for current entitlements
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            do {
                try await updatePurchaseState(from: transaction)
                return
            } catch {
                // Log error but still update in-memory state for current session
                logger.logError(error, context: "Failed to store receipt during entitlement check")

                // REFINEMENT: Give user premium for current session even if storage fails
                // This handles the case where the app was reinstalled and we're recovering from Apple's servers
                let receiptId = "tx_\(transaction.originalID)"
                self.purchaseState = .purchased(receiptId: receiptId)
                self.currentReceiptId = receiptId
                self.isPremium = true

                logger.log("⚠️ User has premium (current session only, storage failed): \(receiptId.prefix(8))...", level: .warning)
                return
            }
        }

        // No valid transactions found
        if currentReceiptId == nil {
            self.purchaseState = .notPurchased
            self.isPremium = false
            logger.log("🚫 No valid purchases found", level: .info)
        }
    }
    
    private func updatePurchaseState(from transaction: StoreKit.Transaction) async throws {
        // Use the original transaction ID as our stable user identifier
        let receiptId = "tx_\(transaction.originalID)"

        // CRITICAL: Store receipt BEFORE updating state or finishing transaction
        try await storeReceiptIdWithRetry(receiptId)

        // Only update state after successful storage
        self.purchaseState = .purchased(receiptId: receiptId)
        self.currentReceiptId = receiptId
        self.isPremium = true

        logger.log("✅ Valid transaction stored and state updated: \(receiptId.prefix(8))...", level: .info)
    }
}

// MARK: - Extensions

extension Product.SubscriptionPeriod.Unit {
    var localizedPluralDescription: String {
        switch self {
        case .day: return "Days"
        case .week: return "Weeks"
        case .month: return "Months"
        case .year: return "Years"
        @unknown default: return "Period"
        }
    }
}