//
//  MenuBarIconView.swift
//  MacMount
//
//  Menu bar icon that shows connection status
//

import SwiftUI

struct MenuBarIconView: View {
    let connectionStatus: ConnectionStatus
    @State private var isAnimating = false
    
    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(iconColor)
            .opacity(opacity)
            .animation(
                connectionStatus == .connecting ?
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                value: isAnimating
            )
            .onAppear {
                isAnimating = connectionStatus == .connecting
            }
            .onChange(of: connectionStatus) { newValue in
                isAnimating = newValue == .connecting
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
    }
    
    private var iconName: String {
        connectionStatus.iconName
    }
    
    private var iconColor: Color {
        switch connectionStatus {
        case .allConnected:
            return .green
        case .partiallyConnected:
            return .orange
        case .disconnected:
            return .secondary
        case .connecting:
            return .blue
        }
    }
    
    private var opacity: Double {
        if connectionStatus == .connecting && isAnimating {
            return 0.7
        } else {
            return 1.0
        }
    }
    
    private var accessibilityLabel: String {
        connectionStatus.displayName
    }
    
    private var accessibilityHint: String {
        connectionStatus.description
    }
}