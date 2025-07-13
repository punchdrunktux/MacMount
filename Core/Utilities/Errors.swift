//
//  Errors.swift
//  MacMount
//
//  Error types used throughout the application
//

import Foundation

enum MountError: LocalizedError, Equatable {
    case serverUnreachable
    case authenticationFailed
    case mountPointInvalid(String)
    case mountFailed(errno: Int32)
    case unmountFailed(errno: Int32)
    case timeoutExceeded
    case vpnRequired
    case quotaExceeded
    case permissionDenied
    case alreadyMounted
    case shareAlreadyMounted(at: String)
    case notMounted
    case staleMount
    case networkUnavailable
    case authenticationRequired
    case credentialNotFound
    case internalError(String)
    
    var isAuthenticationError: Bool {
        switch self {
        case .authenticationFailed, .authenticationRequired, .credentialNotFound, .permissionDenied:
            return true
        default:
            return false
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .serverUnreachable:
            return "Cannot reach the server. Check your network connection."
        case .authenticationFailed:
            return "Invalid username or password."
        case .mountPointInvalid(let reason):
            return "Invalid mount point: \(reason)"
        case .mountFailed(let errno):
            return "Mount failed: \(String(cString: strerror(errno)))"
        case .unmountFailed(let errno):
            return "Unmount failed: \(String(cString: strerror(errno)))"
        case .timeoutExceeded:
            return "Connection timed out."
        case .vpnRequired:
            return "VPN connection required for this share."
        case .quotaExceeded:
            return "Storage quota exceeded."
        case .permissionDenied:
            return "Permission denied. Check your access rights."
        case .alreadyMounted:
            return "Drive is already mounted."
        case .shareAlreadyMounted(let location):
            return "Share is already mounted at \(location)."
        case .notMounted:
            return "Drive is not mounted."
        case .staleMount:
            return "Mount point is stale and needs to be cleaned up."
        case .networkUnavailable:
            return "Network is not available"
        case .authenticationRequired:
            return "Authentication is required for this server"
        case .credentialNotFound:
            return "No saved credentials found for this server"
        case .internalError(let message):
            return "Internal error: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .authenticationFailed:
            return "Check your credentials and try again."
        case .serverUnreachable:
            return "Ensure the server is online and accessible from your network."
        case .vpnRequired:
            return "Connect to VPN and try again."
        case .permissionDenied:
            return "Contact your system administrator for access."
        case .staleMount:
            return "The app will attempt to clean up and remount automatically."
        case .networkUnavailable:
            return "Check your network connection and try again."
        case .authenticationRequired, .credentialNotFound:
            return "Edit the server configuration to provide credentials."
        case .alreadyMounted:
            return "The share is already mounted. Check existing mounts or unmount first."
        case .shareAlreadyMounted(let location):
            return "The share is already mounted at \(location). Unmount it first or access it at the existing location."
        default:
            return nil
        }
    }
    
    static func == (lhs: MountError, rhs: MountError) -> Bool {
        switch (lhs, rhs) {
        case (.serverUnreachable, .serverUnreachable),
             (.authenticationFailed, .authenticationFailed),
             (.timeoutExceeded, .timeoutExceeded),
             (.vpnRequired, .vpnRequired),
             (.quotaExceeded, .quotaExceeded),
             (.permissionDenied, .permissionDenied),
             (.alreadyMounted, .alreadyMounted),
             (.notMounted, .notMounted),
             (.staleMount, .staleMount),
             (.networkUnavailable, .networkUnavailable),
             (.authenticationRequired, .authenticationRequired),
             (.credentialNotFound, .credentialNotFound):
            return true
        case let (.mountPointInvalid(reason1), .mountPointInvalid(reason2)):
            return reason1 == reason2
        case let (.mountFailed(errno1), .mountFailed(errno2)):
            return errno1 == errno2
        case let (.unmountFailed(errno1), .unmountFailed(errno2)):
            return errno1 == errno2
        case let (.shareAlreadyMounted(location1), .shareAlreadyMounted(location2)):
            return location1 == location2
        case let (.internalError(message1), .internalError(message2)):
            return message1 == message2
        default:
            return false
        }
    }
}

enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case systemError(OSStatus)
    case dataConversionError
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Credentials not found in keychain."
        case .duplicateItem:
            return "Credentials already exist in keychain."
        case .systemError(let status):
            return "Keychain error: \(status)"
        case .dataConversionError:
            return "Failed to convert credential data."
        case .invalidData:
            return "Invalid credential data in keychain."
        }
    }
}