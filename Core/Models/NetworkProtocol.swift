//
//  NetworkProtocol.swift
//  MacMount
//
//  Supported network file sharing protocols
//

import Foundation

enum NetworkProtocol: String, CaseIterable, Codable, Identifiable {
    case smb = "SMB"
    case afp = "AFP"
    case nfs = "NFS"
    
    var id: String { rawValue }
    
    var displayName: String { rawValue }
    
    var defaultPort: Int {
        switch self {
        case .smb: return 445
        case .afp: return 548
        case .nfs: return 2049
        }
    }
    
    var requiresAuthentication: Bool {
        switch self {
        case .smb, .afp: return true
        case .nfs: return false
        }
    }
    
    var supportsGuestAccess: Bool {
        switch self {
        case .smb: return true
        case .afp: return true
        case .nfs: return true
        }
    }
    
    var mountCommand: String {
        switch self {
        case .smb: return "mount_smbfs"
        case .afp: return "mount_afp"
        case .nfs: return "mount_nfs"
        }
    }
}