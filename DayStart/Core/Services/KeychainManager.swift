import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    // MARK: - Generic Keychain Operations
    
    private func keychainQuery(for key: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.daystart.app"
        ]
    }
    
    // MARK: - Store Data
    
    func store<T: Codable>(_ value: T, forKey key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else {
            return false
        }
        
        return storeData(data, forKey: key)
    }
    
    func storeData(_ data: Data, forKey key: String) -> Bool {
        var query = keychainQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Retrieve Data
    
    func retrieve<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = retrieveData(forKey: key) else {
            return nil
        }
        
        return try? JSONDecoder().decode(type, from: data)
    }
    
    func retrieveData(forKey key: String) -> Data? {
        var query = keychainQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            return nil
        }
        
        return result as? Data
    }
    
    // MARK: - Delete Data
    
    func delete(forKey key: String) -> Bool {
        let query = keychainQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Check Existence
    
    func exists(forKey key: String) -> Bool {
        var query = keychainQuery(for: key)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Clear All App Data
    
    func clearAll() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.daystart.app"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - Keychain Keys

extension KeychainManager {
    enum Keys {
        static let userSettings = "user_settings"
        static let schedule = "schedule"
        static let history = "history"
    }
}