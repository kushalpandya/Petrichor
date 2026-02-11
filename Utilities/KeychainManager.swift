import Foundation
import Security

enum KeychainManager {
    enum Keys {
        static let lastfmSessionKey = "org.Petrichor.lastfm.sessionKey"
    }
    
    // MARK: - Save
    
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            Logger.error("KeychainManager: Failed to encode value for key: \(key)")
            return false
        }
        
        // Delete existing item first
        delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            Logger.info("KeychainManager: Saved value for key: \(key)")
            return true
        } else {
            Logger.error("KeychainManager: Failed to save value for key: \(key), status: \(status)")
            return false
        }
    }
    
    // MARK: - Retrieve
    
    static func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    // MARK: - Delete
    
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            Logger.info("KeychainManager: Deleted key: \(key)")
            return true
        } else {
            Logger.error("KeychainManager: Failed to delete key: \(key), status: \(status)")
            return false
        }
    }
    
    // MARK: - Exists
    
    static func exists(key: String) -> Bool {
        retrieve(key: key) != nil
    }
}
