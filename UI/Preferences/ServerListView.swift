//
//  ServerListView.swift
//  MacMount
//
//  Server list management view
//

import SwiftUI

struct ServerListView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedServerId: UUID?
    @State private var showingAddServer = false
    @State private var showingEditServer = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        HSplitView {
            // Server list
            serverList
                .frame(minWidth: 250, idealWidth: 300)
            
            // Detail view
            if let selectedServer = selectedServer {
                ServerDetailView(server: selectedServer)
                    .frame(minWidth: 400)
            } else {
                emptyDetailView
                    .frame(minWidth: 400)
            }
        }
        .sheet(isPresented: $showingAddServer) {
            ServerConfigurationView(mode: .add) { newServer in
                Task {
                    try await appState.addServer(newServer)
                }
            }
        }
        .sheet(isPresented: $showingEditServer) {
            if let server = selectedServer {
                ServerConfigurationView(mode: .edit, server: server) { updatedServer in
                    Task {
                        try await appState.updateServer(updatedServer)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Server?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteServer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let server = selectedServer {
                Text("Are you sure you want to delete '\(server.displayName)'? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Server List
    
    private var serverList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Servers")
                    .font(.headline)
                Spacer()
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: addServer) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Add Server")
                    
                    Button(action: editServer) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(selectedServerId == nil)
                    .help("Edit Server")
                    
                    Button(action: confirmDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(selectedServerId == nil)
                    .help("Delete Server")
                }
            }
            .padding()
            
            Divider()
            
            // List
            if appState.servers.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(appState.servers) { server in
                            ServerListItem(
                                server: server,
                                mountState: appState.mountStates[server.id] ?? .unmounted,
                                isSelected: selectedServerId == server.id,
                                onTap: {
                                    selectedServerId = server.id
                                }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No servers configured")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Click the + button to add a server")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var emptyDetailView: some View {
        VStack {
            Image(systemName: "sidebar.left")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Select a server to view details")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helpers
    
    private var selectedServer: ServerConfiguration? {
        guard let id = selectedServerId else { return nil }
        return appState.servers.first { $0.id == id }
    }
    
    private func addServer() {
        showingAddServer = true
    }
    
    private func editServer() {
        guard selectedServerId != nil else { return }
        showingEditServer = true
    }
    
    private func confirmDelete() {
        guard selectedServerId != nil else { return }
        showingDeleteConfirmation = true
    }
    
    private func deleteServer() {
        guard let id = selectedServerId else { return }
        Task {
            try await appState.removeServer(id)
            selectedServerId = nil
        }
    }
}

// MARK: - Server List Item

struct ServerListItem: View {
    let server: ServerConfiguration
    let mountState: MountState
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            // Server info
            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(.system(.body))
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Image(systemName: protocolIcon)
                        .font(.caption)
                    Text(server.serverAddress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // No mount state indicators in configuration view
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())  // Make entire area clickable
        .onTapGesture {
            onTap()
        }
    }
    
    private var protocolIcon: String {
        switch server.protocol {
        case .smb:
            return "pc"
        case .afp:
            return "applelogo"
        case .nfs:
            return "server.rack"
        }
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
        case .mounting:
            return .blue
        case .unmounting:
            return .orange
        case .error:
            return .red
        case .stale:
            return .yellow
        case .unmounted:
            return .gray
        case .disabled:
            return .secondary
        }
    }
}

// MARK: - Server Detail View

struct ServerDetailView: View {
    let server: ServerConfiguration
    @EnvironmentObject var appState: AppState
    @StateObject private var connectionLogger = ConnectionLogger.shared
    
    // Use actual mount state from app state
    private var mountState: MountState {
        appState.mountStates[server.id] ?? .unmounted
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection
                
                // Configuration
                configurationSection
                
                // Connection Logs
                connectionLogsSection
            }
            .padding()
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: server.protocol == .afp ? "applelogo" : "server.rack")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text(server.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(server.protocol.rawValue) Server")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Connect/Disconnect buttons
                HStack(spacing: 8) {
                    Button(action: {
                        Task {
                            await appState.mountServer(server)
                        }
                    }) {
                        if case .mounting = mountState {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 14, height: 14)
                                Text("Connecting...")
                            }
                        } else {
                            Label("Connect", systemImage: "cable.connector")
                        }
                    }
                    .disabled(!canConnect)
                    .buttonStyle(.borderedProminent)
                    .help(canConnect ? "Connect to server" : connectDisabledReason)
                    
                    Button(action: {
                        Task {
                            await appState.unmountServer(id: server.id)
                        }
                    }) {
                        if case .unmounting = mountState {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 14, height: 14)
                                Text("Disconnecting...")
                            }
                        } else {
                            Label("Disconnect", systemImage: "cable.connector.slash")
                        }
                    }
                    .disabled(!canDisconnect)
                    .buttonStyle(.bordered)
                    .help(canDisconnect ? "Disconnect from server" : disconnectDisabledReason)
                }
            }
        }
    }
    
    private var canConnect: Bool {
        switch mountState {
        case .unmounted, .error, .stale:
            return true
        case .mounted(.stale):
            return true
        case .mounted(.connected), .mounted(.degraded), .mounted(.validating), .mounting, .unmounting:
            return false
        case .disabled:
            return true // Can connect to enable
        }
    }
    
    private var canDisconnect: Bool {
        switch mountState {
        case .mounted(_), .stale:
            return true
        case .unmounted, .mounting, .unmounting, .error, .disabled:
            return false
        }
    }
    
    private var connectDisabledReason: String {
        switch mountState {
        case .mounted:
            return "Already connected"
        case .mounting:
            return "Connection in progress"
        case .unmounting:
            return "Disconnection in progress"
        default:
            return "Cannot connect"
        }
    }
    
    private var disconnectDisabledReason: String {
        switch mountState {
        case .unmounted:
            return "Already disconnected"
        case .mounting:
            return "Connection in progress"
        case .unmounting:
            return "Disconnection in progress"
        case .error:
            return "Not connected"
        default:
            return "Cannot disconnect"
        }
    }
    
    private var configurationSection: some View {
        GroupBox("Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "Protocol", value: server.protocol.displayName)
                DetailRow(label: "Server Address", value: server.serverAddress)
                DetailRow(label: "Share Name", value: server.shareName)
                DetailRow(label: "Mount Point", value: server.effectiveMountPoint)
                if !server.username.isEmpty {
                    DetailRow(label: "Username", value: server.username)
                }
                DetailRow(label: "Requires VPN", value: server.requiresVPN ? "Yes" : "No")
                DetailRow(label: "Read Only", value: server.readOnly ? "Yes" : "No")
                DetailRow(label: "Hidden Mount", value: server.hiddenMount ? "Yes" : "No")
                DetailRow(label: "Retry Strategy", value: server.retryStrategy.displayName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    
    @State private var displayedLogCount = 20
    
    private var serverLogs: [ConnectionLogEntry] {
        connectionLogger.logs
            .filter { $0.serverId == server.id }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    private var connectionLogsSection: some View {
        GroupBox("Connection Logs") {
            VStack(alignment: .leading, spacing: 8) {
                if serverLogs.isEmpty {
                    Text("No logs available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    // Show limited logs with stable IDs
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(serverLogs.prefix(displayedLogCount).enumerated()), id: \.element.id) { index, entry in
                                ConnectionLogRow(entry: entry)
                                    .id(entry.id)
                                if index < serverLogs.prefix(displayedLogCount).count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    
                    HStack {
                        Text("\(serverLogs.count) total log entries")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if serverLogs.count > displayedLogCount {
                            Button("Show More") {
                                withAnimation {
                                    displayedLogCount += 20
                                }
                            }
                            .font(.caption)
                        }
                        
                        Button("Clear Logs") {
                            ConnectionLogger.shared.clearLogs(for: server.id)
                        }
                        .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Connection Log Row

struct ConnectionLogRow: View {
    let entry: ConnectionLogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Icon based on level
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.caption)
                .frame(width: 16)
            
            // Timestamp
            Text(entry.timestamp, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            
            // Message
            Text(entry.message)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var iconName: String {
        switch entry.level {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.circle"
        }
    }
    
    private var iconColor: Color {
        switch entry.level {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)
            
            Text(value)
                .font(.body)
                .textSelection(.enabled)
            
            Spacer()
        }
    }
}