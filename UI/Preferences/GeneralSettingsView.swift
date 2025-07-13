//
//  GeneralSettingsView.swift
//  MacMount
//
//  General application settings
//

import SwiftUI
import ServiceManagement
import OSLog

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("autoMountOnWake") private var autoMountOnWake = true
    @AppStorage("autoMountOnNetworkChange") private var autoMountOnNetworkChange = true
    @AppStorage("showDebugLogs") private var showDebugLogs = false
    
    var body: some View {
        Form {
            startupSection
            behaviorSection
            notificationSection
            debugSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
    
    // MARK: - Startup Section
    private var startupSection: some View {
        Section("Startup") {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    configureLoginItem(enabled: newValue)
                }
                .help("Automatically start MacMount when you log in")
        }
    }
    
    // MARK: - Behavior Section
    private var behaviorSection: some View {
        Section("Behavior") {
            Toggle("Auto-mount on Wake", isOn: $autoMountOnWake)
                .help("Automatically mount drives when Mac wakes from sleep")
            
            Toggle("Auto-mount on Network Change", isOn: $autoMountOnNetworkChange)
                .help("Automatically mount drives when network connection changes")
        }
    }
    
    // MARK: - Notification Section
    private var notificationSection: some View {
        Section("Notifications") {
            Toggle("Show Notifications", isOn: $showNotifications)
                .help("Show notifications for mount/unmount events")
            
            if showNotifications {
                Text("Configure notification settings in System Settings > Notifications")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Debug Section
    private var debugSection: some View {
        Section("Debug") {
            Toggle("Show Debug Logs", isOn: $showDebugLogs)
                .help("Enable verbose logging for troubleshooting")
            
            Button("Export Logs...") {
                exportLogs()
            }
            .help("Export diagnostic logs for support")
            
            Button("Show Log Files") {
                showLogFiles()
            }
            .help("Open log file location in Finder")
            
            Button("Reset All Settings") {
                resetSettings()
            }
            .foregroundColor(.red)
            .help("Reset all settings to defaults")
        }
    }
    
    // MARK: - Actions
    private func configureLoginItem(enabled: Bool) {
        if #available(macOS 13.0, *) {
            // Use new ServiceManagement API
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Logger.system.error("Failed to configure login item: \(error)")
            }
        } else {
            // Use legacy API for older macOS versions
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.example.macmount"
            SMLoginItemSetEnabled(bundleIdentifier as CFString, enabled)
        }
    }
    
    private func exportLogs() {
        Task {
            do {
                let diagnostics = DiagnosticsCollector()
                let logURL = try await diagnostics.exportLogs(since: Date().addingTimeInterval(-86400)) // Last 24 hours
                
                await MainActor.run {
                    let savePanel = NSSavePanel()
                    savePanel.allowedContentTypes = [.plainText]
                    savePanel.nameFieldStringValue = "MacMount-Logs.txt"
                    
                    if savePanel.runModal() == .OK, let url = savePanel.url {
                        try? FileManager.default.copyItem(at: logURL, to: url)
                    }
                }
            } catch {
                Logger.system.error("Failed to export logs: \(error)")
            }
        }
    }
    
    private func resetSettings() {
        // Reset UserDefaults
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
            UserDefaults.standard.synchronize()
        }
    }
    
    private func showLogFiles() {
        let logsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MacMount")
            .appendingPathComponent("Logs")
        
        if let logsDirectory = logsDirectory {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logsDirectory.path)
        }
    }
}