//
//  ConnectionLogsView.swift
//  MacMount
//
//  View for displaying connection logs
//

import SwiftUI
import OSLog
import UniformTypeIdentifiers

struct ConnectionLogsView: View {
    @StateObject private var connectionLogger = ConnectionLogger.shared
    @EnvironmentObject var appState: AppState
    @State private var selectedServerId: UUID?
    @State private var selectedLevel: ConnectionLogEntry.LogLevel?
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var scrollToBottom = false
    
    // Cache for filtered logs
    @State private var cachedFilteredLogs: [ConnectionLogEntry] = []
    @State private var cacheKey: FilterCacheKey = FilterCacheKey()
    
    // Date formatter for log display
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
    
    var filteredLogs: [ConnectionLogEntry] {
        // Create new cache key
        let newCacheKey = FilterCacheKey(
            logsCount: connectionLogger.logs.count,
            selectedServerId: selectedServerId,
            selectedLevel: selectedLevel,
            searchText: searchText
        )
        
        // If cache key hasn't changed, return cached results
        if newCacheKey == cacheKey {
            return cachedFilteredLogs
        }
        
        // Cache miss - recompute
        var logs = connectionLogger.logs
        
        // Filter by server
        if let serverId = selectedServerId {
            logs = logs.filter { $0.serverId == serverId }
        }
        
        // Filter by level
        if let level = selectedLevel {
            logs = logs.filter { $0.level == level }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            logs = logs.filter { 
                $0.message.lowercased().contains(lowercasedSearch) ||
                $0.serverName.lowercased().contains(lowercasedSearch)
            }
        }
        
        // Sort once
        let sortedLogs = logs.sorted { $0.timestamp > $1.timestamp }
        
        // Update cache
        DispatchQueue.main.async {
            self.cachedFilteredLogs = sortedLogs
            self.cacheKey = newCacheKey
        }
        
        return sortedLogs
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with filters
            headerView
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Logs list
            if filteredLogs.isEmpty {
                emptyStateView
            } else {
                logsListView
            }
            
            Divider()
            
            // Footer with actions
            footerView
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle("Connection Logs")
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            // Server filter
            Picker("Server", selection: $selectedServerId) {
                Text("All Servers")
                    .tag(UUID?.none)
                
                Divider()
                
                ForEach(appState.servers) { server in
                    Text(server.displayName)
                        .tag(UUID?.some(server.id))
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(maxWidth: 200)
            
            // Level filter
            Picker("Level", selection: $selectedLevel) {
                Text("All Levels")
                    .tag(ConnectionLogEntry.LogLevel?.none)
                
                Divider()
                
                ForEach(ConnectionLogEntry.LogLevel.allCases, id: \.self) { level in
                    Label(level.rawValue, systemImage: level.symbolName)
                        .tag(ConnectionLogEntry.LogLevel?.some(level))
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(maxWidth: 150)
            
            Spacer()
            
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 200)
            
            // Auto-scroll toggle
            Toggle(isOn: $autoScroll) {
                Label("Auto-scroll", systemImage: "arrow.down.to.line")
            }
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        }
    }
    
    // MARK: - Logs List View
    
    private var logsListView: some View {
        let logs = filteredLogs
        let attributedString = LogTextView.createAttributedString(
            from: logs,
            dateFormatter: dateFormatter
        )
        
        return LogTextView(
            attributedString: attributedString,
            autoScroll: autoScroll,
            scrollToBottom: $scrollToBottom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No logs to display")
                .font(.headline)
            
            Text("Connection logs will appear here when servers attempt to connect")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Footer View
    
    private var footerView: some View {
        HStack {
            Text("\(filteredLogs.count) log entries")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if !autoScroll {
                Button(action: { scrollToBottom = true }) {
                    Label("Scroll to Bottom", systemImage: "arrow.down.to.line")
                }
                .disabled(filteredLogs.isEmpty)
            }
            
            Button(action: clearLogs) {
                Label("Clear Logs", systemImage: "trash")
            }
            .disabled(filteredLogs.isEmpty)
            
            Button(action: exportLogs) {
                Label("Export...", systemImage: "square.and.arrow.up")
            }
            .disabled(filteredLogs.isEmpty)
        }
    }
    
    // MARK: - Actions
    
    private func clearLogs() {
        connectionLogger.clearLogs(for: selectedServerId)
    }
    
    // MARK: - Export
    
    private func exportLogs() {
        let content = connectionLogger.exportLogs()
        
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacMount_Logs_\(Date().ISO8601Format()).txt"
        panel.allowedContentTypes = [UTType.plainText]
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Logger.system.error("Failed to export logs: \(error)")
            }
        }
    }
}

// MARK: - Log Entry (now using selectable text format)

// MARK: - Filter Cache Key

private struct FilterCacheKey: Equatable {
    let logsCount: Int
    let selectedServerId: UUID?
    let selectedLevel: ConnectionLogEntry.LogLevel?
    let searchText: String
    
    init(logsCount: Int = 0, selectedServerId: UUID? = nil, selectedLevel: ConnectionLogEntry.LogLevel? = nil, searchText: String = "") {
        self.logsCount = logsCount
        self.selectedServerId = selectedServerId
        self.selectedLevel = selectedLevel
        self.searchText = searchText
    }
}

// MARK: - Preview

struct ConnectionLogsView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectionLogsView()
            .environmentObject(AppState())
    }
}