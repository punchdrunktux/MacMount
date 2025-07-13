//
//  Logger+Extensions.swift
//  MacMount
//
//  Logging utilities and extensions
//

import OSLog
import Foundation

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.macmount"
    
    // Logger instances for different subsystems
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let mount = Logger(subsystem: subsystem, category: "Mount")
    static let credentials = Logger(subsystem: subsystem, category: "Credentials")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let system = Logger(subsystem: subsystem, category: "System")
    static let vpn = Logger(subsystem: subsystem, category: "VPN")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
}

// MARK: - Convenience logging methods
extension Logger {
    func logMountAttempt(_ configuration: ServerConfiguration) {
        self.info("Attempting to mount \(configuration.displayName) using \(configuration.protocol.rawValue)")
    }
    
    func logMountSuccess(_ configuration: ServerConfiguration, mountPoint: String) {
        self.info("Successfully mounted \(configuration.displayName) at \(mountPoint)")
    }
    
    func logMountFailure(_ configuration: ServerConfiguration, error: Error) {
        self.error("Failed to mount \(configuration.displayName): \(error.localizedDescription)")
    }
    
    func logNetworkChange(connected: Bool, type: String?) {
        if connected {
            self.info("Network connected: \(type ?? "Unknown")")
        } else {
            self.warning("Network disconnected")
        }
    }
}

// MARK: - Static convenience methods
extension Logger {
    static func info(_ message: String) {
        Logger.system.info("\(message)")
    }
    
    static func warning(_ message: String) {
        Logger.system.warning("\(message)")
    }
    
    static func error(_ message: String) {
        Logger.system.error("\(message)")
    }
    
    static func debug(_ message: String) {
        #if DEBUG
        Logger.system.debug("\(message)")
        #endif
    }
    
    private static var debugMode = false
    
    static func setDebugMode(_ enabled: Bool) {
        debugMode = enabled
    }
}