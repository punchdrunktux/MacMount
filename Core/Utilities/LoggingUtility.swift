//
//  LoggingUtility.swift
//  MacMount
//
//  Utility for configuring file-based logging
//

import Foundation
import OSLog

/// Utility class for managing application logging to file
@available(macOS 11.0, *)
public final class LoggingUtility {
    static let shared = LoggingUtility()
    
    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    
    private init() {
        // Set up log directory
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("MacMount")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        
        // Create log file with timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        
        logFileURL = logsDirectory.appendingPathComponent("MacMount-\(timestamp).log")
        
        // Set up date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Create initial log entry
        writeLog("=== MacMount Log Started ===")
        writeLog("Log file: \(logFileURL.path)")
    }
    
    /// Write a log message to file
    func writeLog(_ message: String, category: String = "General") {
        let timestamp = dateFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] [\(category)] \(message)\n"
        
        // Append to file
        if let data = logEntry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
    
    /// Get the current log file path
    var currentLogPath: String {
        logFileURL.path
    }
    
    /// Clean up old log files (keep last 10)
    func cleanupOldLogs() {
        guard let logsDirectory = logFileURL.deletingLastPathComponent().path as NSString? else { return }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: logsDirectory as String)
            let logFiles = files.filter { $0.hasPrefix("MacMount-") && $0.hasSuffix(".log") }
                .sorted()
                .reversed()
            
            // Keep only the 10 most recent logs
            if logFiles.count > 10 {
                for file in logFiles.dropFirst(10) {
                    let filePath = logsDirectory.appendingPathComponent(file)
                    try? FileManager.default.removeItem(atPath: filePath)
                }
            }
        } catch {
            // Ignore cleanup errors
        }
    }
}

// MARK: - Logger Extension

@available(macOS 11.0, *)
extension Logger {
    /// Log to both system log and file
    func logToFile(_ message: String, category: String? = nil) {
        // Log to system
        self.info("\(message)")
        
        // Log to file
        let logCategory = category ?? "General"
        LoggingUtility.shared.writeLog(message, category: logCategory)
    }
    
    /// Log error to both system log and file
    func errorToFile(_ message: String, category: String? = nil) {
        // Log to system
        self.error("\(message)")
        
        // Log to file
        let logCategory = category ?? "General"
        LoggingUtility.shared.writeLog("ERROR: \(message)", category: logCategory)
    }
}