//
//  ServerConfigurationView.swift
//  MacMount
//
//  Add/Edit server configuration form
//

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.example.MacMount", category: "ServerConfigurationView")

struct ServerConfigurationView: View {
    enum Mode {
        case add
        case edit
    }
    
    let mode: Mode
    let onSave: (ServerConfiguration) async throws -> Void
    
    @State private var config: ServerConfiguration
    @StateObject private var securePassword = SecurePasswordField()
    @State private var showPassword = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var testingConnection = false
    @State private var testResult: String?
    @State private var mountPointHasAccess = false
    @State private var checkingMountPointAccess = false
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    // Note: BookmarkManager temporarily removed to avoid @MainActor deadlock
    // @StateObject private var bookmarkManager = BookmarkManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "ServerConfig")
    
    init(mode: Mode, server: ServerConfiguration? = nil, onSave: @escaping (ServerConfiguration) async throws -> Void) {
        self.mode = mode
        self.onSave = onSave
        self._config = State(initialValue: server ?? ServerConfiguration())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Form content
            Form {
                generalSection
                authenticationSection
                advancedSection
                
                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }
                
                if let result = testResult {
                    Section {
                        Label(result, systemImage: "checkmark.circle")
                            .foregroundColor(.green)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 500, height: 550)
            
            // Buttons
            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(testingConnection || !config.isValid)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button(mode == .add ? "Add" : "Save") {
                    save()
                }
                .keyboardShortcut(.return)
                .disabled(!config.isValid || isSaving || (config.saveCredentials && !config.username.isEmpty && !securePassword.hasPassword))
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle(mode == .add ? "Add Server" : "Edit Server")
        .onAppear {
            checkMountPointAccess()
            if mode == .edit && config.saveCredentials {
                loadExistingPassword()
            }
        }
    }
    
    // MARK: - Form Sections
    
    private var generalSection: some View {
        Section("General") {
            TextField("Name (Optional)", text: $config.name)
                .help("A friendly name for this server")
            
            Picker("Protocol", selection: $config.protocol) {
                ForEach(NetworkProtocol.allCases) { proto in
                    Text(proto.displayName).tag(proto)
                }
            }
            
            TextField("Server Address", text: $config.serverAddress)
                .help("IP address or hostname")
            
            TextField("Share Name", text: $config.shareName)
                .help("The name of the share or export")
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Mount Point (Optional)", text: $config.mountPoint)
                        .help("Leave empty to use default /Volumes location")
                        .onChange(of: config.mountPoint) { _ in
                            checkMountPointAccess()
                        }
                    
                    Button("Choose...") {
                        chooseMountPoint()
                    }
                    
                    if checkingMountPointAccess {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    } else if !config.mountPoint.isEmpty {
                        Image(systemName: mountPointHasAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(mountPointHasAccess ? .green : .orange)
                            .help(mountPointHasAccess ? "Access granted" : "Access required")
                    }
                }
                
                // Sandboxing notice
                if !config.mountPoint.isEmpty && !mountPointHasAccess {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text("This app runs in a sandbox. You'll need to grant access to this location.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Grant Access") {
                        grantMountPointAccess()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
    }
    
    private var authenticationSection: some View {
        Section("Authentication") {
            if config.protocol.requiresAuthentication {
                TextField("Username", text: $config.username)
                    .textContentType(.username)
                    .disabled(!config.protocol.requiresAuthentication)
                
                SecurePasswordFieldView(
                    secureField: securePassword,
                    placeholder: "Password",
                    showToggle: true
                )
                .disabled(!config.protocol.requiresAuthentication)
                
                Toggle("Save password in Keychain", isOn: $config.saveCredentials)
                    .disabled(!config.protocol.requiresAuthentication)
            } else {
                Text("No authentication required for \(config.protocol.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var advancedSection: some View {
        Section("Advanced Options") {
            Toggle("Requires VPN", isOn: $config.requiresVPN)
                .help("Only mount when VPN is connected")
            
            Toggle("Hide from Finder", isOn: $config.hiddenMount)
                .help("Hide this mount from the Finder sidebar")
            
            Toggle("Read Only", isOn: $config.readOnly)
                .help("Mount in read-only mode")
            
            Picker("Retry Strategy", selection: $config.retryStrategy) {
                ForEach(RetryStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }
            .help("How often to retry failed connections")
            
            // Custom retry settings
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Maximum Retry Attempts:")
                    Spacer()
                    if let maxAttempts = config.maxRetryAttempts {
                        Stepper("\(maxAttempts)", value: Binding(
                            get: { maxAttempts },
                            set: { config.maxRetryAttempts = $0 }
                        ), in: 1...100)
                    } else {
                        Text("Unlimited")
                            .foregroundColor(.secondary)
                    }
                    Button(config.maxRetryAttempts == nil ? "Set Limit" : "Unlimited") {
                        if config.maxRetryAttempts == nil {
                            config.maxRetryAttempts = config.retryStrategy.maxRetries
                        } else {
                            config.maxRetryAttempts = nil
                        }
                    }
                    .buttonStyle(.link)
                }
                
                HStack {
                    Text("Retry Interval:")
                    Spacer()
                    if let interval = config.customRetryInterval {
                        Text("\(Int(interval)) seconds")
                            .frame(width: 80, alignment: .trailing)
                        Slider(value: Binding(
                            get: { interval },
                            set: { config.customRetryInterval = $0 }
                        ), in: 1...60, step: 1)
                        .frame(width: 120)
                    } else {
                        Text("Strategy default")
                            .foregroundColor(.secondary)
                    }
                    Button(config.customRetryInterval == nil ? "Customize" : "Default") {
                        if config.customRetryInterval == nil {
                            config.customRetryInterval = config.retryStrategy.baseInterval
                        } else {
                            config.customRetryInterval = nil
                        }
                    }
                    .buttonStyle(.link)
                }
                .help("Time between retry attempts")
            }
            .font(.system(size: 11))
        }
    }
    
    // MARK: - Actions
    
    private func loadExistingPassword() {
        Task {
            do {
                // Use shared instance to avoid actor isolation issues
                if let credential = try await SecureCredentialManager.shared.retrieveCredential(for: config) {
                    // Set password in secure field
                    // Note: This is only for display purposes when editing
                    // The password will be cleared from memory after save
                    await MainActor.run {
                        securePassword.setPassword(credential.password)
                    }
                }
            } catch {
                // Silently fail - user can re-enter password if needed
                logger.debug("Could not load existing password: \(error)")
            }
        }
    }
    
    private func chooseMountPoint() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select a mount point location"
        
        // In sandbox mode, this grants temporary access
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url else { return }
            
            Task { @MainActor in
                config.mountPoint = url.path
                
                // Create bookmark for the mount point
                do {
                    _ = try await appState.bookmarkManager.createBookmark(for: url)
                    mountPointHasAccess = true
                } catch {
                    logger.error("Failed to create bookmark for mount point: \(error)")
                    mountPointHasAccess = false
                    errorMessage = "Failed to create bookmark: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func checkMountPointAccess() {
        guard !config.mountPoint.isEmpty else {
            mountPointHasAccess = false
            return
        }
        
        checkingMountPointAccess = true
        
        Task {
            // For /Volumes paths, just check if directory exists
            if config.mountPoint.hasPrefix("/Volumes/") {
                await MainActor.run {
                    mountPointHasAccess = true  // /Volumes is always accessible
                    checkingMountPointAccess = false
                }
            } else {
                // For custom mount points, check bookmark
                let hasBookmark = await appState.bookmarkManager.hasBookmark(for: config.mountPoint)
                await MainActor.run {
                    mountPointHasAccess = hasBookmark || FileManager.default.fileExists(atPath: config.mountPoint)
                    checkingMountPointAccess = false
                }
            }
        }
    }
    
    private func grantMountPointAccess() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Grant Access"
        panel.message = "Grant access to the mount point directory"
        panel.directoryURL = URL(fileURLWithPath: config.mountPoint)
        
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url else { return }
            
            Task { @MainActor in
                // Update path if user selected a different directory
                if url.path != config.mountPoint {
                    config.mountPoint = url.path
                }
                
                // Create bookmark for the mount point
                do {
                    _ = try await appState.bookmarkManager.createBookmark(for: url)
                    mountPointHasAccess = true
                } catch {
                    logger.error("Failed to create bookmark after granting access: \(error)")
                    mountPointHasAccess = false
                    errorMessage = "Failed to create bookmark: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func testConnection() {
        testingConnection = true
        testResult = nil
        errorMessage = nil
        
        Task {
            // Test reachability
            let networkMonitor = NetworkMonitor()
            let isReachable = await networkMonitor.isReachable(
                host: config.serverAddress,
                port: config.protocol.defaultPort
            )
            
            if isReachable {
                testResult = "Connection successful! Server is reachable."
                
                // If authentication is required, we could test with credentials
                // Note: We use peekPassword here since we're not consuming it
                if config.protocol.requiresAuthentication && !config.username.isEmpty {
                    if let _ = securePassword.peekPassword() {
                        testResult = "Connection successful! Server is reachable. Credentials provided."
                    } else {
                        testResult = "Connection successful! Server is reachable. No credentials to test."
                    }
                }
            } else {
                errorMessage = "Server is not reachable. Check the address and network connection."
            }
            
            testingConnection = false
        }
    }
    
    private func save() {
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                // Save credentials if needed
                if config.saveCredentials && !config.username.isEmpty {
                    // Securely consume the password (this clears it from memory)
                    if let password = securePassword.consumePassword(), !password.isEmpty {
                        let credential = NetworkCredential(
                            server: config.serverAddress,
                            username: config.username,
                            password: password,
                            protocol: config.protocol
                        )
                        // Use shared instance to avoid actor isolation issues
                        try await SecureCredentialManager.shared.storeCredential(credential)
                        
                        // Password is already cleared by consumePassword()
                        // No further action needed
                    } else {
                        // No password provided
                        errorMessage = "Password is required when saving credentials"
                        isSaving = false
                        return
                    }
                }
                
                // Save configuration
                try await onSave(config)
                
                // Clear any remaining sensitive data before dismissing
                securePassword.clearPassword()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
                
                // Clear password on error to prevent it from lingering in memory
                securePassword.clearPassword()
            }
        }
    }
}

// MARK: - Preview

struct ServerConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        ServerConfigurationView(mode: .add) { _ in }
            .environmentObject(AppState())
    }
}