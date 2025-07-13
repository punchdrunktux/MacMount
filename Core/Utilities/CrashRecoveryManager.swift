//
//  CrashRecoveryManager.swift
//  MacMount
//
//  Handles crash detection and recovery
//

import Foundation
import OSLog

class CrashRecoveryManager {
    static let shared = CrashRecoveryManager()
    
    private let crashKey = "LastCrashInfo"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "CrashRecovery")
    
    private init() {}
    
    func recordCleanShutdown() {
        UserDefaults.standard.removeObject(forKey: crashKey)
        logger.info("Recorded clean shutdown")
    }
    
    func recordStartup() {
        let startupInfo: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "version": Bundle.main.appVersion,
            "build": Bundle.main.buildNumber,
            "system": ProcessInfo.processInfo.operatingSystemVersionString
        ]
        UserDefaults.standard.set(startupInfo, forKey: crashKey)
        logger.info("Recorded startup")
    }
    
    func checkForPreviousCrash() -> Bool {
        let hasCrashInfo = UserDefaults.standard.dictionary(forKey: crashKey) != nil
        if hasCrashInfo {
            logger.warning("Previous crash detected")
        }
        return hasCrashInfo
    }
    
    @MainActor
    func performRecovery() async {
        logger.info("Starting crash recovery")
        
        // Clean up potentially stale mounts
        await cleanupStaleMounts()
        
        // Reset retry counters
        // Note: RetryManager is managed per-instance in MountCoordinator
        
        // Clear any temporary data
        clearTemporaryData()
        
        // Clear crash marker
        recordCleanShutdown()
        
        logger.info("Crash recovery completed")
    }
    
    private func cleanupStaleMounts() async {
        logger.info("Cleaning up stale mounts")
        
        // Get list of expected mount points
        let repository = UserDefaultsServerRepository()
        guard let servers = try? repository.fetchAll() else { return }
        
        for server in servers {
            let mountPoint = server.effectiveMountPoint
            let url = URL(fileURLWithPath: mountPoint)
            
            // Check if mount point exists but is stale
            if FileManager.default.fileExists(atPath: mountPoint) {
                do {
                    // Try to access the mount point
                    _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                } catch {
                    // If we can't access it, it's likely stale
                    logger.warning("Found stale mount at \(mountPoint), attempting cleanup")
                    await attemptUnmount(at: mountPoint)
                }
            }
        }
    }
    
    private func attemptUnmount(at path: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/umount")
        process.arguments = ["-f", path]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                logger.info("Successfully unmounted stale mount at \(path)")
            } else {
                logger.error("Failed to unmount stale mount at \(path)")
            }
        } catch {
            logger.error("Error unmounting stale mount: \(error)")
        }
    }
    
    private func clearTemporaryData() {
        // Clear any temporary keys
        let tempKeys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("temp_") }
        for key in tempKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

// MARK: - Bundle Extensions

extension Bundle {
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    var buildNumber: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
}