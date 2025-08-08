import Foundation

struct StockSymbolItem: Identifiable, Codable, Equatable {
    let id: UUID
    var symbol: String
    
    init(symbol: String = "") {
        self.id = UUID()
        self.symbol = symbol
    }
    
    init(id: UUID, symbol: String) {
        self.id = id
        self.symbol = symbol
    }
    
    static func == (lhs: StockSymbolItem, rhs: StockSymbolItem) -> Bool {
        return lhs.id == rhs.id && lhs.symbol == rhs.symbol
    }
}

// MARK: - Array Extensions for Backwards Compatibility
extension Array where Element == StockSymbolItem {
    /// Convert to array of strings for storage/API compatibility
    var asStringArray: [String] {
        return self.map { $0.symbol }.filter { !$0.isEmpty }
    }
}

extension Array where Element == String {
    /// Convert from array of strings to StockSymbolItems
    var asStockSymbolItems: [StockSymbolItem] {
        return self.map { StockSymbolItem(symbol: $0) }
    }
}