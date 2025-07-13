//
//  ConnectionLogEntry.swift
//  MacMount
//
//  Model for connection log entries
//

import Foundation

struct ConnectionLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let serverId: UUID
    let serverName: String
    let level: LogLevel
    let message: String
    let error: MountError?
    let attemptNumber: Int?
    
    enum LogLevel: String, CaseIterable {
        case info = "Info"
        case warning = "Warning"
        case error = "Error"
        case success = "Success"
        
        var symbolName: String {
            switch self {
            case .info:
                return "info.circle"
            case .warning:
                return "exclamationmark.triangle"
            case .error:
                return "xmark.circle"
            case .success:
                return "checkmark.circle"
            }
        }
        
        var color: String {
            switch self {
            case .info:
                return "blue"
            case .warning:
                return "orange"
            case .error:
                return "red"
            case .success:
                return "green"
            }
        }
    }
}