import Foundation
import Combine

// MARK: - Stock Validation Models
struct StockValidationResult {
    let symbol: String
    let isValid: Bool
    let error: StockValidationError?
    let companyName: String?
}

enum StockValidationError: LocalizedError {
    case tooShort
    case tooLong
    case invalidCharacters
    case notFound
    case apiError(String)
    case networkError
    case rateLimited
    
    var errorDescription: String? {
        switch self {
        case .tooShort:
            return "Symbol must be 1-5 characters"
        case .tooLong:
            return "Symbol must be 1-5 characters"
        case .invalidCharacters:
            return "Only letters allowed"
        case .notFound:
            return "Stock symbol not found"
        case .apiError(let message):
            return "API Error: \(message)"
        case .networkError:
            return "Network connection error"
        case .rateLimited:
            return "Too many requests, please wait"
        }
    }
}

// MARK: - Stock Validation Service
class StockValidationService: ObservableObject {
    static let shared = StockValidationService()
    
    private let logger = DebugLogger.shared
    private var cancellables = Set<AnyCancellable>()
    private var validationCache: [String: StockValidationResult] = [:]
    private var lastAPICall: Date = .distantPast
    private let apiCooldown: TimeInterval = 1.0 // 1 second between API calls
    
    // Known valid symbols for offline validation
    private let knownValidSymbols: Set<String> = [
        "AAPL", "GOOGL", "GOOG", "MSFT", "AMZN", "TSLA", "META", "NVDA", 
        "JPM", "JNJ", "V", "PG", "UNH", "HD", "DIS", "MA", "PYPL", "BAC",
        "NFLX", "ADBE", "CRM", "CMCSA", "XOM", "VZ", "KO", "PFE", "INTC",
        "CSCO", "PEP", "T", "MRK", "WMT", "ABT", "CVX", "COST", "TMO",
        "AVGO", "DHR", "TXN", "LLY", "ACN", "NEE", "UPS", "PM", "BMY",
        "QCOM", "HON", "LIN", "UNP", "ORCL", "AMD", "COP", "WFC", "SPGI",
        "GS", "BLK", "LOW", "C", "MS", "CAT", "RTX", "IBM", "AMGN", "AXP",
        "SPY", "QQQ", "IWM", "VTI", "VOO", "VEA", "IEFA", "AGG", "LQD"
    ]
    
    private init() {}
    
    // MARK: - Public API
    func validateSymbol(_ symbol: String) -> StockValidationResult {
        let cleanSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // Check cache first
        if let cachedResult = validationCache[cleanSymbol] {
            return cachedResult
        }
        
        // Basic validation
        if let basicError = performBasicValidation(cleanSymbol) {
            let result = StockValidationResult(
                symbol: cleanSymbol,
                isValid: false,
                error: basicError,
                companyName: nil
            )
            validationCache[cleanSymbol] = result
            return result
        }
        
        // Check known valid symbols
        if knownValidSymbols.contains(cleanSymbol) {
            let result = StockValidationResult(
                symbol: cleanSymbol,
                isValid: true,
                error: nil,
                companyName: getKnownCompanyName(for: cleanSymbol)
            )
            validationCache[cleanSymbol] = result
            return result
        }
        
        // For unknown symbols, mark as potentially valid but unverified
        // In the future, this is where we'd call the API
        let result = StockValidationResult(
            symbol: cleanSymbol,
            isValid: true, // Assume valid for now
            error: nil,
            companyName: nil
        )
        validationCache[cleanSymbol] = result
        return result
    }
    
    func validateSymbolAsync(_ symbol: String, completion: @escaping (StockValidationResult) -> Void) {
        let cleanSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // If we have cached result, return immediately
        if let cachedResult = validationCache[cleanSymbol] {
            DispatchQueue.main.async {
                completion(cachedResult)
            }
            return
        }
        
        // Perform validation on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let result = self.validateSymbol(cleanSymbol)
            
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    // MARK: - Private Methods
    private func performBasicValidation(_ symbol: String) -> StockValidationError? {
        if symbol.isEmpty || symbol.count < 1 {
            return .tooShort
        }
        
        if symbol.count > 5 {
            return .tooLong
        }
        
        if !symbol.allSatisfy({ $0.isLetter && $0.isASCII }) {
            return .invalidCharacters
        }
        
        return nil
    }
    
    private func getKnownCompanyName(for symbol: String) -> String? {
        // Simple mapping for demo purposes
        let companyNames: [String: String] = [
            "AAPL": "Apple Inc.",
            "GOOGL": "Alphabet Inc.",
            "MSFT": "Microsoft Corp.",
            "AMZN": "Amazon.com Inc.",
            "TSLA": "Tesla Inc.",
            "META": "Meta Platforms Inc.",
            "NVDA": "NVIDIA Corp.",
            "SPY": "SPDR S&P 500 ETF",
            "QQQ": "Invesco QQQ ETF"
        ]
        return companyNames[symbol]
    }
    
    // MARK: - API Integration (Future)
    /*
    private func validateWithAPI(_ symbol: String, completion: @escaping (StockValidationResult) -> Void) {
        // Rate limiting
        let now = Date()
        if now.timeIntervalSince(lastAPICall) < apiCooldown {
            // Too soon, return cached or basic validation
            completion(validateSymbol(symbol))
            return
        }
        lastAPICall = now
        
        // Future: Call Supabase function for stock validation
        // This would make a request to a Supabase Edge Function that validates stocks
        // using a financial API like Alpha Vantage, Yahoo Finance, or Polygon.io
        
        logger.log("🔍 Would validate stock symbol with API: \(symbol)", level: .debug)
        
        // For now, just use local validation
        completion(validateSymbol(symbol))
    }
    */
    
    func clearCache() {
        validationCache.removeAll()
        logger.log("🗑️ Stock validation cache cleared", level: .debug)
    }
}