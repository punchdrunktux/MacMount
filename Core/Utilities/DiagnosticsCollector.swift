//
//  DiagnosticsCollector.swift
//  MacMount
//
//  Collects diagnostic information for troubleshooting
//

import Foundation
import OSLog

struct DiagnosticReport: Codable {
    let timestamp: Date
    let systemInfo: SystemInfo
    let networkStatus: NetworkStatus
    let mountedDrives: [MountedDrive]
    let recentErrors: [LogEntry]
    let configuration: AppConfiguration
}

struct SystemInfo: Codable {
    let osVersion: String
    let appVersion: String
    let buildNumber: String
    let uptime: TimeInterval
    let memoryUsage: Double
}

struct NetworkStatus: Codable {
    let isConnected: Bool
    let connectionType: String?
    let isVPNConnected: Bool
}

struct MountedDrive: Codable {
    let path: String
    let protocolType: String
    let status: String
    
    enum CodingKeys: String, CodingKey {
        case path
        case protocolType = "protocol"
        case status
    }
}

struct LogEntry: Codable {
    let timestamp: Date
    let category: String
    let level: String
    let message: String
}

struct AppConfiguration: Codable {
    let serverCount: Int
    let launchAtLogin: Bool
    let autoMountEnabled: Bool
}

class DiagnosticsCollector {
    
    func generateDiagnosticReport() async -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            systemInfo: await gatherSystemInfo(),
            networkStatus: await gatherNetworkStatus(),
            mountedDrives: await gatherMountedDrives(),
            recentErrors: await gatherRecentErrors(),
            configuration: await gatherConfiguration()
        )
    }
    
    private func gatherSystemInfo() async -> SystemInfo {
        let processInfo = ProcessInfo.processInfo
        
        return SystemInfo(
            osVersion: processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            uptime: processInfo.systemUptime,
            memoryUsage: Double(processInfo.physicalMemory)
        )
    }
    
    private func gatherNetworkStatus() async -> NetworkStatus {
        let networkMonitor = NetworkMonitor()
        let vpnMonitor = VPNMonitor()
        
        // Give monitors a moment to initialize
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        return NetworkStatus(
            isConnected: await networkMonitor.isConnected,
            connectionType: await networkMonitor.connectionType?.description,
            isVPNConnected: await vpnMonitor.isVPNConnected
        )
    }
    
    private func gatherMountedDrives() async -> [MountedDrive] {
        let repository = UserDefaultsServerRepository()
        let servers = (try? repository.fetchAll()) ?? []
        var drives: [MountedDrive] = []
        
        for server in servers {
            let status = await checkMountStatus(server.effectiveMountPoint)
            drives.append(MountedDrive(
                path: server.effectiveMountPoint,
                protocolType: server.protocol.rawValue,
                status: status
            ))
        }
        
        return drives
    }
    
    private func checkMountStatus(_ path: String) async -> String {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: path) {
            return "Not Mounted"
        }
        
        do {
            _ = try fileManager.contentsOfDirectory(atPath: path)
            return "Mounted"
        } catch {
            return "Stale"
        }
    }
    
    private func gatherRecentErrors() async -> [LogEntry] {
        // Note: In a real implementation, this would query the system log
        // For now, return empty array
        return []
    }
    
    private func gatherConfiguration() async -> AppConfiguration {
        let defaults = UserDefaults.standard
        let repository = UserDefaultsServerRepository()
        
        return AppConfiguration(
            serverCount: (try? repository.fetchAll())?.count ?? 0,
            launchAtLogin: defaults.bool(forKey: "launchAtLogin"),
            autoMountEnabled: defaults.bool(forKey: "autoMountOnNetworkChange")
        )
    }
    
    func exportLogs(since date: Date) async throws -> URL {
        let logs = try await gatherLogs(since: date)
        
        // Create temporary file
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacMount-Logs-\(Date().timeIntervalSince1970).txt")
        
        let logContent = logs.map { entry in
            "[\(entry.timestamp)] \(entry.category): \(entry.message)"
        }.joined(separator: "\n")
        
        try logContent.write(to: exportURL, atomically: true, encoding: .utf8)
        return exportURL
    }
    
    private func gatherLogs(since date: Date) async throws -> [LogEntry] {
        // In a real implementation, this would use OSLogStore
        // For now, return sample data
        return [
            LogEntry(
                timestamp: Date(),
                category: "System",
                level: "Info",
                message: "MacMount diagnostic export"
            )
        ]
    }
}