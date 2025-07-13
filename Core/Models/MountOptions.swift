//
//  MountOptions.swift
//  MacMount
//
//  Options for mount operations
//

import Foundation

struct MountOptions {
    var softMount: Bool = true
    var noUI: Bool = true
    var hidden: Bool = false
    var readOnly: Bool = false
    var timeout: TimeInterval = 30
    var retryCount: Int = 3
    
    // Protocol-specific options
    var smbVersion: SMBVersion?
    var nfsVersion: NFSVersion?
    
    init() {}
    
    // Create from ServerConfiguration
    init(from config: ServerConfiguration) {
        self.hidden = config.hiddenMount
        self.readOnly = config.readOnly
    }
    
    // Convert to mount command arguments
    func toCommandArguments(for protocol: NetworkProtocol) -> [String] {
        var options: [String] = []
        
        // Common options
        if softMount {
            options.append("soft")
        }
        
        if hidden {
            options.append("nobrowse")
        }
        
        if readOnly {
            options.append("rdonly")
        }
        
        // Protocol-specific options
        switch `protocol` {
        case .smb:
            if let version = smbVersion {
                options.append("vers=\(version.rawValue)")
            }
        case .nfs:
            if let version = nfsVersion {
                options.append("vers=\(version.rawValue)")
            }
            // Add common NFS options
            options.append("resvport")
        case .afp:
            // AFP-specific options if needed
            break
        }
        
        // Combine all options into a single -o argument
        if !options.isEmpty {
            return ["-o", options.joined(separator: ",")]
        }
        
        return []
    }
}

enum SMBVersion: String {
    case v1 = "1.0"
    case v2 = "2.0"
    case v3 = "3.0"
}

enum NFSVersion: Int {
    case v3 = 3
    case v4 = 4
}