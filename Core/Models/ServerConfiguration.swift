//
//  ServerConfiguration.swift
//  MacMount
//
//  Model representing a network drive configuration
//

import Foundation

// MARK: - Management State
enum ManagementState: String, Codable {
    case enabled    // The app should actively try to keep this mounted
    case disabled   // The user has turned this off, ignore completely
}

struct ServerConfiguration: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var `protocol`: NetworkProtocol
    var serverAddress: String
    var shareName: String
    var mountPoint: String
    var username: String
    var requiresVPN: Bool
    var hiddenMount: Bool
    var readOnly: Bool
    var retryStrategy: RetryStrategy
    var saveCredentials: Bool
    var managementState: ManagementState
    
    // Custom retry settings
    var maxRetryAttempts: Int? // nil = unlimited
    var customRetryInterval: TimeInterval? // nil = use strategy default
    
    // Computed properties
    var displayName: String {
        name.isEmpty ? "\(serverAddress)/\(shareName)" : name
    }
    
    var isValid: Bool {
        !serverAddress.isEmpty && !shareName.isEmpty
    }
    
    var effectiveMaxRetries: Int {
        maxRetryAttempts ?? retryStrategy.maxRetries
    }
    
    var effectiveRetryInterval: TimeInterval {
        customRetryInterval ?? retryStrategy.baseInterval
    }
    
    var effectiveMountPoint: String {
        if mountPoint.isEmpty {
            // Default to user's home directory to avoid permission issues
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            return "\(homeDir)/NetworkDrives/\(shareName.replacingOccurrences(of: " ", with: "_"))"
        }
        return mountPoint
    }
    
    var mountURL: URL? {
        var components = URLComponents()
        
        switch `protocol` {
        case .smb:
            components.scheme = "smb"
        case .afp:
            components.scheme = "afp"
        case .nfs:
            components.scheme = "nfs"
        }
        
        components.host = serverAddress
        components.path = "/\(shareName)"
        
        return components.url
    }
    
    // Initializer with defaults
    init(id: UUID = UUID(),
         name: String = "",
         protocol: NetworkProtocol = .smb,
         serverAddress: String = "",
         shareName: String = "",
         mountPoint: String = "",
         username: String = "",
         requiresVPN: Bool = false,
         hiddenMount: Bool = false,
         readOnly: Bool = false,
         retryStrategy: RetryStrategy = .normal,
         saveCredentials: Bool = true,
         managementState: ManagementState = .enabled,
         maxRetryAttempts: Int? = nil,
         customRetryInterval: TimeInterval? = nil) {
        self.id = id
        self.name = name
        self.protocol = `protocol`
        self.serverAddress = serverAddress
        self.shareName = shareName
        self.mountPoint = mountPoint
        self.username = username
        self.requiresVPN = requiresVPN
        self.hiddenMount = hiddenMount
        self.readOnly = readOnly
        self.retryStrategy = retryStrategy
        self.saveCredentials = saveCredentials
        self.managementState = managementState
        self.maxRetryAttempts = maxRetryAttempts
        self.customRetryInterval = customRetryInterval
    }
}

// MARK: - Hashable

extension ServerConfiguration: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}