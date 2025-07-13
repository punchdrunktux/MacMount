//
//  MountResult.swift
//  MacMount
//
//  Result of a mount operation
//

import Foundation

struct MountResult {
    let success: Bool
    let mountPoint: String
    let `protocol`: NetworkProtocol
    let mountedAt: Date
    let message: String?
    
    init(success: Bool, 
         mountPoint: String, 
         protocol: NetworkProtocol, 
         mountedAt: Date = Date(), 
         message: String? = nil) {
        self.success = success
        self.mountPoint = mountPoint
        self.protocol = `protocol`
        self.mountedAt = mountedAt
        self.message = message
    }
    
    static func failure(message: String, protocol: NetworkProtocol) -> MountResult {
        MountResult(
            success: false, 
            mountPoint: "", 
            protocol: `protocol`, 
            message: message
        )
    }
}