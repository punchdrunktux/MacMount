//
//  ConnectionStatus.swift
//  MacMount
//
//  Overall connection status for the menu bar icon
//

import Foundation

enum ConnectionStatus: String, CaseIterable {
    case allConnected
    case partiallyConnected
    case disconnected
    case connecting
    
    var displayName: String {
        switch self {
        case .allConnected:
            return "All Connected"
        case .partiallyConnected:
            return "Partially Connected"
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        }
    }
    
    var iconName: String {
        switch self {
        case .allConnected:
            return "externaldrive.fill.badge.checkmark"
        case .partiallyConnected:
            return "externaldrive.fill.badge.minus"
        case .disconnected:
            return "externaldrive.badge.xmark"
        case .connecting:
            return "externaldrive.fill.badge.questionmark"
        }
    }
    
    var description: String {
        switch self {
        case .allConnected:
            return "All network drives are connected"
        case .partiallyConnected:
            return "Some network drives are connected"
        case .disconnected:
            return "No network drives are connected"
        case .connecting:
            return "Connecting to network drives"
        }
    }
}