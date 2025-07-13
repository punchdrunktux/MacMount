//
//  MockKeychain.swift
//  MacMountTests
//
//  Mock implementation of Keychain operations for testing
//

import Foundation
import Security

/// Mock keychain for testing credential storage without actual keychain access
class MockKeychain {
    enum MockKeychainError: Error {
        case itemNotFound
        case duplicateItem
        case invalidQuery
        case operationFailed(OSStatus)
    }
    
    private var storage: [String: [String: Any]] = [:]
    private let queue = DispatchQueue(label: "MockKeychain", attributes: .concurrent)
    
    // Control behavior
    var shouldFailNextOperation = false
    var nextOperationError: OSStatus = errSecSuccess
    var operationDelay: TimeInterval = 0
    
    func reset() {
        queue.sync(flags: .barrier) {
            storage.removeAll()
            shouldFailNextOperation = false
            nextOperationError = errSecSuccess
            operationDelay = 0
        }
    }
    
    // MARK: - Keychain Operations
    
    func add(_ attributes: [String: Any]) -> OSStatus {
        guard !shouldFailNextOperation else {
            shouldFailNextOperation = false
            return nextOperationError
        }
        
        if operationDelay > 0 {
            Thread.sleep(forTimeInterval: operationDelay)
        }
        
        return queue.sync(flags: .barrier) {
            guard let service = attributes[kSecAttrService as String] as? String,
                  let account = attributes[kSecAttrAccount as String] as? String else {
                return errSecParam
            }
            
            let key = "\(service):\(account)"
            
            // Check for duplicate
            if storage[key] != nil {
                return errSecDuplicateItem
            }
            
            // Store the item
            storage[key] = attributes
            return errSecSuccess
        }
    }
    
    func update(_ query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus {
        guard !shouldFailNextOperation else {
            shouldFailNextOperation = false
            return nextOperationError
        }
        
        if operationDelay > 0 {
            Thread.sleep(forTimeInterval: operationDelay)
        }
        
        return queue.sync(flags: .barrier) {
            guard let service = query[kSecAttrService as String] as? String,
                  let account = query[kSecAttrAccount as String] as? String else {
                return errSecParam
            }
            
            let key = "\(service):\(account)"
            
            // Check if item exists
            guard var existingItem = storage[key] else {
                return errSecItemNotFound
            }
            
            // Update attributes
            for (attrKey, attrValue) in attributesToUpdate {
                existingItem[attrKey] = attrValue
            }
            
            storage[key] = existingItem
            return errSecSuccess
        }
    }
    
    func delete(_ query: [String: Any]) -> OSStatus {
        guard !shouldFailNextOperation else {
            shouldFailNextOperation = false
            return nextOperationError
        }
        
        if operationDelay > 0 {
            Thread.sleep(forTimeInterval: operationDelay)
        }
        
        return queue.sync(flags: .barrier) {
            guard let service = query[kSecAttrService as String] as? String else {
                return errSecParam
            }
            
            if let account = query[kSecAttrAccount as String] as? String {
                // Delete specific item
                let key = "\(service):\(account)"
                if storage.removeValue(forKey: key) != nil {
                    return errSecSuccess
                } else {
                    return errSecItemNotFound
                }
            } else {
                // Delete all items for service
                let keysToDelete = storage.keys.filter { $0.hasPrefix("\(service):") }
                if keysToDelete.isEmpty {
                    return errSecItemNotFound
                }
                
                for key in keysToDelete {
                    storage.removeValue(forKey: key)
                }
                return errSecSuccess
            }
        }
    }
    
    func copyMatching(_ query: [String: Any], result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        guard !shouldFailNextOperation else {
            shouldFailNextOperation = false
            return nextOperationError
        }
        
        if operationDelay > 0 {
            Thread.sleep(forTimeInterval: operationDelay)
        }
        
        return queue.sync {
            guard let service = query[kSecAttrService as String] as? String else {
                return errSecParam
            }
            
            let matchLimit = query[kSecMatchLimit as String] as? String
            
            if let account = query[kSecAttrAccount as String] as? String {
                // Find specific item
                let key = "\(service):\(account)"
                guard let item = storage[key] else {
                    return errSecItemNotFound
                }
                
                if let result = result {
                    result.pointee = createResult(from: item, returnAttributes: query[kSecReturnAttributes as String] as? Bool ?? false,
                                                 returnData: query[kSecReturnData as String] as? Bool ?? false)
                }
                return errSecSuccess
            } else if matchLimit == kSecMatchLimitAll as String {
                // Find all items for service
                let matchingItems = storage.compactMap { key, value -> [String: Any]? in
                    guard key.hasPrefix("\(service):") else { return nil }
                    return value
                }
                
                if matchingItems.isEmpty {
                    return errSecItemNotFound
                }
                
                if let result = result {
                    let returnAttributes = query[kSecReturnAttributes as String] as? Bool ?? false
                    let returnData = query[kSecReturnData as String] as? Bool ?? false
                    
                    let results = matchingItems.map { item in
                        createResult(from: item, returnAttributes: returnAttributes, returnData: returnData)
                    }
                    
                    result.pointee = results as CFArray
                }
                return errSecSuccess
            }
            
            return errSecItemNotFound
        }
    }
    
    // MARK: - Helper Methods
    
    private func createResult(from item: [String: Any], returnAttributes: Bool, returnData: Bool) -> CFTypeRef {
        var result: [String: Any] = [:]
        
        if returnAttributes {
            result[kSecAttrService as String] = item[kSecAttrService as String]
            result[kSecAttrAccount as String] = item[kSecAttrAccount as String]
            result[kSecAttrLabel as String] = item[kSecAttrLabel as String]
            result[kSecAttrAccessGroup as String] = item[kSecAttrAccessGroup as String]
        }
        
        if returnData {
            result[kSecValueData as String] = item[kSecValueData as String]
        }
        
        return result as CFDictionary
    }
    
    // MARK: - Test Helpers
    
    func getAllItems() -> [[String: Any]] {
        queue.sync {
            Array(storage.values)
        }
    }
    
    func itemCount() -> Int {
        queue.sync {
            storage.count
        }
    }
    
    func containsItem(service: String, account: String) -> Bool {
        queue.sync {
            let key = "\(service):\(account)"
            return storage[key] != nil
        }
    }
}

// MARK: - Keychain Operation Helpers

/// Helper to replace actual keychain operations with mock in tests
struct KeychainOperations {
    static var mock: MockKeychain?
    
    static func add(_ attributes: [String: Any]) -> OSStatus {
        if let mock = mock {
            return mock.add(attributes)
        }
        return SecItemAdd(attributes as CFDictionary, nil)
    }
    
    static func update(_ query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus {
        if let mock = mock {
            return mock.update(query, attributesToUpdate: attributesToUpdate)
        }
        return SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
    }
    
    static func delete(_ query: [String: Any]) -> OSStatus {
        if let mock = mock {
            return mock.delete(query)
        }
        return SecItemDelete(query as CFDictionary)
    }
    
    static func copyMatching(_ query: [String: Any], result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        if let mock = mock {
            return mock.copyMatching(query, result: result)
        }
        return SecItemCopyMatching(query as CFDictionary, result)
    }
}