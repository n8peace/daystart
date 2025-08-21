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
    
    private let logger = DebugLogger.shared
    private let keychainManager = KeychainManager.shared
    private let receiptKey = "purchase_receipt_id"
    
    private init() {
        Task {
            await checkPurchaseStatus()
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
    
    func simulatePurchase(for productId: String) async throws {
        // This simulates a successful purchase for testing
        // In production, this would be replaced with actual StoreKit purchase flow
        logger.log("🛒 Simulating purchase for product: \(productId)", level: .info)
        await MainActor.run { isLoading = true }
        
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Generate a mock receipt ID (in production this comes from StoreKit)
        let mockReceiptId = "tx_\(UUID().uuidString.prefix(16))"
        
        // Store the receipt ID
        keychainManager.store(mockReceiptId, forKey: receiptKey)
        
        await MainActor.run {
            self.purchaseState = .purchased(receiptId: mockReceiptId)
            self.currentReceiptId = mockReceiptId
        }
        
        logger.log("✅ Purchase simulation complete: \(mockReceiptId)", level: .info)
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
                
                logger.log("✅ Purchase successful: \(receiptId.prefix(8))...", level: .info)
                
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
    
    private func clearStoredReceipt() {
        keychainManager.delete(forKey: receiptKey)
        currentReceiptId = nil
        purchaseState = .notPurchased
        logger.log("🧹 Cleared stored receipt", level: .info)
    }
}