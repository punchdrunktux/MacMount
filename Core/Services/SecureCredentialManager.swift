//
//  SecureCredentialManager.swift
//  MacMount
//
//  Manages secure credential storage using macOS Keychain
//

import Security
import OSLog

actor SecureCredentialManager {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "Credentials")
    
    // Shared instance to avoid creating multiple actor instances
    static let shared = SecureCredentialManager()
    
    // MARK: - Store Credentials
    
    func storeCredential(_ credential: NetworkCredential) async throws {
        // Direct async operation without continuation bridging
        try await performStore(credential: credential)
    }
    
    private func performStore(credential: NetworkCredential) async throws {
        guard let passwordData = credential.password.data(using: .utf8) else {
            throw KeychainError.dataConversionError
        }
        
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: credential.server,
            kSecAttrAccount as String: credential.username,
            kSecAttrPort as String: credential.port,
            kSecAttrProtocol as String: protocolIdentifier(for: credential.protocol),
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: false,
            kSecAttrLabel as String: "MacMount: \(credential.server)"
        ]
        
        // First, try to update existing item
        let query = searchQuery(for: credential)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: passwordData,
            kSecAttrLabel as String: "MacMount: \(credential.server)"
        ]
        
        var status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        
        if status == errSecItemNotFound {
            // Item doesn't exist, add it
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        
        switch status {
        case errSecSuccess:
            logger.info("Credential stored successfully for \(credential.server)")
        case errSecDuplicateItem:
            logger.error("Duplicate credential for \(credential.server)")
            throw KeychainError.duplicateItem
        default:
            logger.error("Keychain error \(status) for \(credential.server)")
            throw KeychainError.systemError(status)
        }
    }
    
    // MARK: - Retrieve Credentials
    
    func retrieveCredential(for config: ServerConfiguration) async throws -> NetworkCredential? {
        guard config.saveCredentials && !config.username.isEmpty else {
            return nil
        }
        
        return try await performRetrieve(for: config)
    }
    
    private func performRetrieve(for config: ServerConfiguration) async throws -> NetworkCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: config.serverAddress,
            kSecAttrAccount as String: config.username,
            kSecAttrProtocol as String: protocolIdentifier(for: config.protocol),
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        switch status {
        case errSecSuccess:
            guard let existingItem = item as? [String: Any],
                  let passwordData = existingItem[kSecValueData as String] as? Data,
                  let password = String(data: passwordData, encoding: .utf8) else {
                logger.error("Failed to decode credential for \(config.serverAddress)")
                throw KeychainError.invalidData
            }
            
            let credential = NetworkCredential(
                server: config.serverAddress,
                username: config.username,
                password: password,
                port: config.protocol.defaultPort,
                protocol: config.protocol
            )
            
            logger.info("Retrieved credential for \(config.serverAddress)")
            return credential
            
        case errSecItemNotFound:
            logger.info("No credential found for \(config.serverAddress)")
            return nil
            
        default:
            logger.error("Keychain retrieval error \(status) for \(config.serverAddress)")
            throw KeychainError.systemError(status)
        }
    }
    
    // MARK: - Delete Credentials
    
    func deleteCredential(for config: ServerConfiguration) async throws {
        try await performDelete(for: config)
    }
    
    private func performDelete(for config: ServerConfiguration) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: config.serverAddress,
            kSecAttrAccount as String: config.username,
            kSecAttrProtocol as String: protocolIdentifier(for: config.protocol)
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        switch status {
        case errSecSuccess, errSecItemNotFound:
            logger.info("Credential deleted for \(config.serverAddress)")
        default:
            logger.error("Failed to delete credential: \(status)")
            throw KeychainError.systemError(status)
        }
    }
    
    // MARK: - Helper Methods
    
    private func searchQuery(for credential: NetworkCredential) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: credential.server,
            kSecAttrAccount as String: credential.username,
            kSecAttrPort as String: credential.port,
            kSecAttrProtocol as String: protocolIdentifier(for: credential.protocol)
        ]
    }
    
    private func protocolIdentifier(for networkProtocol: NetworkProtocol) -> CFString {
        switch networkProtocol {
        case .smb:
            return kSecAttrProtocolSMB
        case .afp:
            return kSecAttrProtocolAFP
        case .nfs:
            // NFS doesn't have a predefined constant, use custom string
            return "nfs" as CFString
        }
    }
    
    // MARK: - Batch Operations
    
    func deleteAllCredentials() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: "MacMount" as CFString
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        switch status {
        case errSecSuccess, errSecItemNotFound:
            logger.info("All credentials deleted")
        default:
            logger.error("Failed to delete all credentials: \(status)")
            throw KeychainError.systemError(status)
        }
    }
}