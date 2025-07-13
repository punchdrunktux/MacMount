//
//  ConnectionLogger.swift
//  MacMount
//
//  Service for logging connection attempts and errors
//

import Foundation
import OSLog
import SwiftUI

@MainActor
class ConnectionLogger: ObservableObject {
    static let shared = ConnectionLogger()
    
    @Published private(set) var logs: [ConnectionLogEntry] = []
    private let maxLogsPerServer = 100
    private let maxTotalLogs = 500
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "ConnectionLogger")
    
    // Background queue for file I/O operations
    private let ioQueue = DispatchQueue(label: "com.networkdrivemapper.connectionlogger.io", qos: .background)
    
    // Actor for thread-safe log file operations
    private let fileWriter = LogFileWriter()
    
    private init() {
        // Log location for debugging
        if let logPath = getLogFilePath() {
            logger.info("Connection logs location: \(logPath)")
        }
    }
    
    // MARK: - Logging Methods
    
    func logMountAttempt(server: ServerConfiguration, attempt: Int, maxAttempts: Int) {
        let entry = ConnectionLogEntry(
            timestamp: Date(),
            serverId: server.id,
            serverName: server.displayName,
            level: .info,
            message: "Mount attempt \(attempt) of \(maxAttempts)",
            error: nil,
            attemptNumber: attempt
        )
        
        addEntry(entry)
        logger.info("Mount attempt \(attempt)/\(maxAttempts) for \(server.displayName)")
    }
    
    func logMountSuccess(server: ServerConfiguration, attempt: Int) {
        let entry = ConnectionLogEntry(
            timestamp: Date(),
            serverId: server.id,
            serverName: server.displayName,
            level: .success,
            message: "Successfully mounted on attempt \(attempt)",
            error: nil,
            attemptNumber: attempt
        )
        
        addEntry(entry)
        logger.info("Successfully mounted \(server.displayName) on attempt \(attempt)")
    }
    
    func logMountError(server: ServerConfiguration, error: MountError, attempt: Int) {
        let entry = ConnectionLogEntry(
            timestamp: Date(),
            serverId: server.id,
            serverName: server.displayName,
            level: .error,
            message: error.localizedDescription,
            error: error,
            attemptNumber: attempt
        )
        
        addEntry(entry)
        logger.error("Mount error for \(server.displayName) on attempt \(attempt): \(error.localizedDescription)")
    }
    
    func logNetworkCheck(server: ServerConfiguration, reachable: Bool) {
        let entry = ConnectionLogEntry(
            timestamp: Date(),
            serverId: server.id,
            serverName: server.displayName,
            level: reachable ? .info : .warning,
            message: reachable ? "Server is reachable" : "Server is not reachable",
            error: nil,
            attemptNumber: nil
        )
        
        addEntry(entry)
        logger.info("Network check for \(server.displayName): \(reachable ? "reachable" : "unreachable")")
    }
    
    func logRetryDelay(server: ServerConfiguration, delay: TimeInterval, attempt: Int) {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        let delayString = formatter.string(from: delay) ?? "\(Int(delay))s"
        
        let entry = ConnectionLogEntry(
            timestamp: Date(),
            serverId: server.id,
            serverName: server.displayName,
            level: .info,
            message: "Waiting \(delayString) before retry",
            error: nil,
            attemptNumber: attempt
        )
        
        addEntry(entry)
        logger.info("Waiting \(delayString) before retry for \(server.displayName)")
    }
    
    func logInfo(server: ServerConfiguration, message: String) {
        let entry = ConnectionLogEntry(
            timestamp: Date(),
            serverId: server.id,
            serverName: server.displayName,
            level: .info,
            message: message,
            error: nil,
            attemptNumber: nil
        )
        
        addEntry(entry)
        logger.info("\(server.displayName): \(message)")
    }
    
    // MARK: - Management Methods
    
    func clearLogs(for serverId: UUID? = nil) {
        if let serverId = serverId {
            logs.removeAll { $0.serverId == serverId }
        } else {
            logs.removeAll()
        }
    }
    
    func getLatestError(for serverId: UUID) -> ConnectionLogEntry? {
        return logs
            .filter { $0.serverId == serverId && $0.level == .error }
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }
    
    func getLogs(for serverId: UUID) -> [ConnectionLogEntry] {
        return logs
            .filter { $0.serverId == serverId }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Private Methods
    
    private func addEntry(_ entry: ConnectionLogEntry) {
        // Add the new entry
        logs.append(entry)
        
        // Write to disk asynchronously on background queue
        Task {
            await fileWriter.writeLog(entry)
        }
        
        // Trim logs per server
        let serverLogs = logs.filter { $0.serverId == entry.serverId }
        if serverLogs.count > maxLogsPerServer {
            let logsToKeep = serverLogs.suffix(maxLogsPerServer)
            logs.removeAll { log in
                log.serverId == entry.serverId && !logsToKeep.contains(log)
            }
        }
        
        // Trim total logs
        if logs.count > maxTotalLogs {
            logs = Array(logs.suffix(maxTotalLogs))
        }
    }
    
    // Moved to LogFileWriter actor below
    
    // MARK: - Export
    
    func exportLogs() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        
        var output = "MacMount Connection Logs\n"
        output += "Generated: \(formatter.string(from: Date()))\n"
        output += String(repeating: "-", count: 80) + "\n\n"
        
        for log in logs.sorted(by: { $0.timestamp < $1.timestamp }) {
            output += "[\(formatter.string(from: log.timestamp))] "
            output += "[\(log.level.rawValue.uppercased())] "
            output += "\(log.serverName): "
            output += log.message
            if let attempt = log.attemptNumber {
                output += " (Attempt \(attempt))"
            }
            output += "\n"
        }
        
        return output
    }
    
    // MARK: - Debug Helpers
    
    func getLogFilePath() -> String? {
        let logsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MacMount")
            .appendingPathComponent("Logs")
        
        guard let logsDirectory = logsDirectory else { return nil }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "connection-log-\(dateFormatter.string(from: Date())).txt"
        
        return logsDirectory.appendingPathComponent(fileName).path
    }
}

// MARK: - Log File Writer Actor

/// Thread-safe actor for writing logs to disk on background queue
private actor LogFileWriter {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "LogFileWriter")
    private var fileHandleCache: [URL: FileHandle] = [:]
    private let dateFormatter: DateFormatter
    private let fileDateFormatter: DateFormatter
    
    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"
    }
    
    func writeLog(_ entry: ConnectionLogEntry) async {
        let logMessage = "[\(dateFormatter.string(from: entry.timestamp))] [\(entry.level.rawValue.uppercased())] \(entry.serverName): \(entry.message)"
        
        // Get or create logs directory
        let logsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MacMount")
            .appendingPathComponent("Logs")
        
        guard let logsDirectory = logsDirectory else { return }
        
        do {
            // Create directory if needed
            if !FileManager.default.fileExists(atPath: logsDirectory.path) {
                try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            }
            
            // Create log file name with today's date
            let fileName = "connection-log-\(fileDateFormatter.string(from: Date())).txt"
            let logFileURL = logsDirectory.appendingPathComponent(fileName)
            
            // Write to file efficiently
            if let data = (logMessage + "\n").data(using: .utf8) {
                try await writeData(data, to: logFileURL)
            }
            
            // Also log to system console for debugging
            logger.debug("\(logMessage)")
            
        } catch {
            logger.error("Failed to write log to disk: \(error)")
        }
    }
    
    private func writeData(_ data: Data, to url: URL) async throws {
        // Check if we have a cached file handle
        if let fileHandle = fileHandleCache[url] {
            try fileHandle.seekToEndOfFile()
            try fileHandle.write(contentsOf: data)
        } else {
            // Create or open file
            if FileManager.default.fileExists(atPath: url.path) {
                let fileHandle = try FileHandle(forWritingTo: url)
                fileHandleCache[url] = fileHandle
                try fileHandle.seekToEndOfFile()
                try fileHandle.write(contentsOf: data)
            } else {
                try data.write(to: url)
                // Cache the file handle for future writes
                if let fileHandle = try? FileHandle(forWritingTo: url) {
                    fileHandleCache[url] = fileHandle
                }
            }
        }
    }
    
    deinit {
        // Close all file handles
        for (_, handle) in fileHandleCache {
            try? handle.close()
        }
    }
}