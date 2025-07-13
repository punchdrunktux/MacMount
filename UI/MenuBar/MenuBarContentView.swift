//
//  MenuBarContentView.swift
//  MacMount
//
//  Main menu bar dropdown content
//

import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredServerId: UUID?
    @State private var hoveredItem: String?
    weak var appDelegate: AppDelegate?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider()
                .padding(.vertical, 4)
            
            // Server list
            if appState.servers.isEmpty {
                emptyStateView
            } else {
                serverListSection
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Actions
            actionsSection
            
            Divider()
                .padding(.vertical, 4)
            
            // Footer - Force it to show
            footerSection
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Image(systemName: appState.overallStatus.iconName)
                .font(.title3)
                .foregroundColor(statusColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("MacMount")
                    .font(.headline)
                Text(appState.overallStatus.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
    
    // MARK: - Server List
    
    private var serverListSection: some View {
        VStack(spacing: 2) {
            ForEach(appState.servers) { server in
                Button(action: {
                    Task {
                        await appState.toggleMount(for: server.id)
                    }
                }) {
                    ServerMenuItem(
                        server: server,
                        mountState: appState.mountStates[server.id] ?? .unmounted,
                        isHovered: hoveredServerId == server.id,
                        isEnabled: server.managementState == .enabled
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredServerId = hovering ? server.id : nil
                }
                .contextMenu {
                    // Enable/Disable toggle
                    Button(server.managementState == .enabled ? "Disable" : "Enable") {
                        Task {
                            await appState.toggleServerEnabled(for: server.id)
                        }
                    }
                    
                    Divider()
                    
                    Button("Edit...") {
                        appDelegate?.showSettingsWindow(nil)
                        // TODO: Navigate to edit view
                    }
                    
                    Button("Delete", role: .destructive) {
                        Task {
                            try? await appState.removeServer(server.id)
                        }
                    }
                    
                    Divider()
                    
                    // Show stop/cancel option based on current state
                    if let state = appState.mountStates[server.id] {
                        switch state {
                        case .mounting(_, _, _):
                            Button("Cancel Connection") {
                                Task {
                                    await appState.stopRetrying(for: server.id)
                                }
                            }
                        case .error:
                            Button("Stop Retrying") {
                                Task {
                                    await appState.stopRetrying(for: server.id)
                                }
                            }
                        default:
                            EmptyView()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("No servers configured")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Add Server") {
                appDelegate?.showSettingsWindow(nil)
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 0) {
            StandardMenuItem(
                id: "preferences",
                action: {
                    if let delegate = appDelegate {
                        // Close popover first
                        delegate.popover?.performClose(nil)
                        // Show settings window immediately
                        delegate.showSettingsWindow(nil)
                    }
                },
                label: {
                    Label("Preferences...", systemImage: "gear")
                        .font(.body)
                },
                hoveredItem: $hoveredItem
            )
            .keyboardShortcut(",", modifiers: .command)
        }
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        VStack(spacing: 0) {
            StandardMenuItem(
                id: "about",
                action: {
                    // Activate app first to ensure About window appears on top
                    NSApp.activate(ignoringOtherApps: true)
                    NSApplication.shared.orderFrontStandardAboutPanel()
                },
                label: {
                    Text("About MacMount")
                        .font(.body)
                },
                hoveredItem: $hoveredItem
            )
            
            StandardMenuItem(
                id: "quit",
                action: {
                    NSApplication.shared.terminate(nil)
                },
                label: {
                    Text("Quit")
                        .font(.body)
                },
                hoveredItem: $hoveredItem
            )
        }
    }
    
    // MARK: - Helpers
    
    private var statusColor: Color {
        switch appState.overallStatus {
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
}

// MARK: - Server Menu Item

struct ServerMenuItem: View {
    let server: ServerConfiguration
    let mountState: MountState
    let isHovered: Bool
    let isEnabled: Bool
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 8) {
            // Enable/Disable toggle
            Toggle("", isOn: Binding(
                get: { server.managementState == .enabled },
                set: { _ in
                    Task {
                        await appState.toggleServerEnabled(for: server.id)
                    }
                }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            .labelsHidden()
            .scaleEffect(0.75)
            .frame(width: 35)
            
            // Status icon
            Image(systemName: isEnabled ? mountState.statusSymbol : "xmark.circle.fill")
                .foregroundColor(isEnabled ? statusColor : .gray)
                .frame(width: 20)
            
            // Server info
            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(.system(.body))
                    .lineLimit(1)
                    .opacity(isEnabled ? 1.0 : 0.6)
                
                HStack(spacing: 4) {
                    Text("\(server.protocol.rawValue) • \(server.serverAddress)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .opacity(isEnabled ? 1.0 : 0.6)
                    
                    // Show error indicator or last error during mounting
                    if case .error(let error) = mountState {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .help(error.localizedDescription)
                    } else if case .mounting(_, _, let lastError) = mountState,
                              let error = lastError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .help("Last error: \(error.localizedDescription)")
                    }
                }
            }
            
            Spacer()
            
            // Mount state
            if case .mounting(let attempt, let maxAttempts, let lastError) = mountState {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("\(attempt)/\(maxAttempts)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .help(lastError != nil ? "Retrying after: \(lastError!.localizedDescription)\nRight-click to cancel" : "Mounting... Right-click to cancel")
            } else if mountState.isTransitioning {
                ProgressView()
                    .scaleEffect(0.7)
                    .help("Right-click to cancel")
            } else if case .error(let error) = mountState,
                      error.isAuthenticationError {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .help("Authentication failed")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }
    
    private var statusColor: Color {
        switch mountState {
        case .mounted(let health):
            switch health {
            case .connected:
                return .green
            case .degraded:
                return .orange
            case .validating:
                return .blue
            case .stale:
                return .red
            }
        case .mounting, .unmounting:
            return .blue
        case .error:
            return .red
        case .stale:
            return .orange
        case .unmounted:
            return .secondary
        case .disabled:
            return .gray
        }
    }
}

// MARK: - Standard Menu Item

struct StandardMenuItem<Label: View>: View {
    let id: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Binding var hoveredItem: String?
    
    var isHovered: Bool {
        hoveredItem == id
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                label()
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItem = hovering ? id : nil
        }
    }
}