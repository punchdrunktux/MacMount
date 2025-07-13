//
//  FirstRunSetupView.swift
//  MacMount
//
//  First-run setup experience for sandboxed environment
//

import SwiftUI

/// Guides users through initial setup in sandboxed environment
struct FirstRunSetupView: View {
    @StateObject private var viewModel = FirstRunSetupViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Content based on current step
            Group {
                switch viewModel.currentStep {
                case .welcome:
                    WelcomeStepView()
                case .permissions:
                    PermissionsStepView(viewModel: viewModel)
                case .migration:
                    MigrationStepView(viewModel: viewModel)
                case .complete:
                    CompleteStepView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            
            // Navigation buttons
            navigationButtons
        }
        .frame(width: 600, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("MacMount Setup")
                .font(.title)
                .fontWeight(.semibold)
            
            // Progress indicator
            HStack(spacing: 20) {
                ForEach(SetupStep.allCases) { step in
                    Circle()
                        .fill(step.rawValue <= viewModel.currentStep.rawValue ? 
                              Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var navigationButtons: some View {
        HStack {
            // Back button
            Button("Back") {
                viewModel.previousStep()
            }
            .disabled(!viewModel.canGoBack)
            
            Spacer()
            
            // Skip button (only for migration step)
            if viewModel.currentStep == .migration {
                Button("Skip") {
                    viewModel.skipMigration()
                }
            }
            
            // Next/Complete button
            Button(viewModel.currentStep == .complete ? "Get Started" : "Next") {
                if viewModel.currentStep == .complete {
                    dismiss()
                } else {
                    viewModel.nextStep()
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!viewModel.canProceed)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Step Views

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("Enhanced Security")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("MacMount now runs in a secure sandbox environment, providing better protection for your data.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 400)
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "lock.fill",
                    title: "Sandboxed Environment",
                    description: "Runs with limited system access for enhanced security"
                )
                
                FeatureRow(
                    icon: "folder.badge.person.crop",
                    title: "Explicit Permissions",
                    description: "You control which folders the app can access"
                )
                
                FeatureRow(
                    icon: "key.fill",
                    title: "Secure Credential Storage",
                    description: "Passwords stored safely in the macOS Keychain"
                )
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

struct PermissionsStepView: View {
    @ObservedObject var viewModel: FirstRunSetupViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Mount Point Access")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("To mount network drives, the app needs access to specific folders on your system.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 400)
            
            // Common mount points
            VStack(alignment: .leading, spacing: 12) {
                Text("Grant access to these common mount locations:")
                    .font(.headline)
                
                ForEach(viewModel.commonMountPoints, id: \.path) { mountPoint in
                    MountPointPermissionRow(
                        mountPoint: mountPoint,
                        onGrant: { viewModel.grantAccess(to: $0) }
                    )
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Custom mount point
            Button("Add Custom Mount Point...") {
                viewModel.selectCustomMountPoint()
            }
            .buttonStyle(.link)
        }
    }
}

struct MigrationStepView: View {
    @ObservedObject var viewModel: FirstRunSetupViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.orange)
            
            Text("Migrate Existing Configuration")
                .font(.title2)
                .fontWeight(.semibold)
            
            if viewModel.existingServers.isEmpty {
                Text("No existing server configurations found.")
                    .foregroundColor(.secondary)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                    .padding()
            } else {
                Text("We found existing server configurations. Grant access to their mount points to continue using them.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 400)
                
                // Migration status
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.migrationResults, id: \.server.id) { result in
                            MigrationStatusRow(result: result)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                if viewModel.isMigrating {
                    ProgressView("Migrating...")
                        .progressViewStyle(.linear)
                        .padding()
                }
            }
        }
    }
}

struct CompleteStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("Setup Complete!")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("MacMount is ready to manage your network drives securely.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 400)
            
            VStack(alignment: .leading, spacing: 16) {
                NextStepRow(
                    icon: "plus.circle",
                    text: "Add your network drives in Preferences"
                )
                
                NextStepRow(
                    icon: "network",
                    text: "Connect to your network or VPN"
                )
                
                NextStepRow(
                    icon: "play.fill",
                    text: "Drives will mount automatically"
                )
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct MountPointPermissionRow: View {
    let mountPoint: SetupMountPointInfo
    let onGrant: (SetupMountPointInfo) -> Void
    
    var body: some View {
        HStack {
            Image(systemName: mountPoint.isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(mountPoint.isGranted ? .green : .secondary)
            
            VStack(alignment: .leading) {
                Text(mountPoint.displayName)
                    .font(.headline)
                Text(mountPoint.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !mountPoint.isGranted {
                Button("Grant Access") {
                    onGrant(mountPoint)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MigrationStatusRow: View {
    let result: SetupMigrationResult
    
    var body: some View {
        HStack {
            Image(systemName: result.status.icon)
                .foregroundColor(result.status.color)
            
            Text(result.server.displayName)
                .lineLimit(1)
            
            Spacer()
            
            Text(result.status.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct NextStepRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            Text(text)
                .font(.body)
        }
    }
}

// MARK: - View Model

@MainActor
class FirstRunSetupViewModel: ObservableObject {
    @Published var currentStep: SetupStep = .welcome
    @Published var commonMountPoints: [SetupMountPointInfo] = []
    @Published var existingServers: [ServerConfiguration] = []
    @Published var migrationResults: [SetupMigrationResult] = []
    @Published var isMigrating = false
    
    private let bookmarkManager = BookmarkManager()
    private let serverRepository = UserDefaultsServerRepository()
    
    init() {
        setupCommonMountPoints()
        loadExistingServers()
    }
    
    // MARK: - Navigation
    
    var canGoBack: Bool {
        currentStep != .welcome
    }
    
    var canProceed: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .permissions:
            // At least one mount point must be granted
            return !commonMountPoints.filter { $0.isGranted }.isEmpty
        case .migration:
            return !isMigrating
        case .complete:
            return true
        }
    }
    
    func nextStep() {
        guard let nextIndex = SetupStep.allCases.firstIndex(of: currentStep)?.advanced(by: 1),
              nextIndex < SetupStep.allCases.count else { return }
        
        currentStep = SetupStep.allCases[nextIndex]
        
        // Start migration when entering migration step
        if currentStep == .migration && !existingServers.isEmpty {
            Task {
                await startMigration()
            }
        }
    }
    
    func previousStep() {
        guard let prevIndex = SetupStep.allCases.firstIndex(of: currentStep)?.advanced(by: -1),
              prevIndex >= 0 else { return }
        
        currentStep = SetupStep.allCases[prevIndex]
    }
    
    func skipMigration() {
        currentStep = .complete
    }
    
    // MARK: - Permissions
    
    func grantAccess(to mountPoint: SetupMountPointInfo) {
        let openPanel = NSOpenPanel()
        openPanel.message = "Grant access to \(mountPoint.displayName)"
        openPanel.prompt = "Grant Access"
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.directoryURL = URL(fileURLWithPath: mountPoint.path)
        
        openPanel.begin { [weak self] response in
            guard response == .OK,
                  let url = openPanel.url else { return }
            
            Task { @MainActor in
                do {
                    _ = try await self?.bookmarkManager.createBookmark(for: url)
                    
                    // Update mount point status
                    if let index = self?.commonMountPoints.firstIndex(where: { $0.path == mountPoint.path }) {
                        self?.commonMountPoints[index].isGranted = true
                    }
                } catch {
                    // Handle error
                    print("Failed to create bookmark: \(error)")
                }
            }
        }
    }
    
    func selectCustomMountPoint() {
        let openPanel = NSOpenPanel()
        openPanel.message = "Select a custom mount point directory"
        openPanel.prompt = "Select"
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        
        openPanel.begin { [weak self] response in
            guard response == .OK,
                  let url = openPanel.url else { return }
            
            Task { @MainActor in
                do {
                    _ = try await self?.bookmarkManager.createBookmark(for: url)
                    
                    // Add to mount points list
                    let customMountPoint = SetupMountPointInfo(
                        path: url.path,
                        displayName: url.lastPathComponent,
                        isGranted: true
                    )
                    self?.commonMountPoints.append(customMountPoint)
                } catch {
                    print("Failed to create bookmark: \(error)")
                }
            }
        }
    }
    
    // MARK: - Migration
    
    private func startMigration() async {
        isMigrating = true
        
        // Create migration results for each server
        migrationResults = existingServers.map { server in
            SetupMigrationResult(
                server: server,
                status: .pending
            )
        }
        
        // Migrate each server's mount point
        for (index, server) in existingServers.enumerated() {
            // Check if bookmark already exists
            if await bookmarkManager.hasBookmark(for: server.mountPoint) {
                migrationResults[index].status = MigrationStatus.success
                continue
            }
            
            // Check if directory exists
            let url = URL(fileURLWithPath: server.mountPoint)
            var isDirectory: ObjCBool = false
            
            if FileManager.default.fileExists(atPath: server.mountPoint, isDirectory: &isDirectory),
               isDirectory.boolValue {
                migrationResults[index].status = MigrationStatus.needsPermission
            } else {
                // Try to create directory
                do {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    migrationResults[index].status = MigrationStatus.needsPermission
                } catch {
                    migrationResults[index].status = MigrationStatus.failed(error.localizedDescription)
                }
            }
        }
        
        isMigrating = false
    }
    
    // MARK: - Setup
    
    private func setupCommonMountPoints() {
        // Default mount points
        let defaultPaths = [
            ("/Volumes", "Volumes"),
            ("~/Desktop/NetworkDrives", "Desktop Network Drives"),
            ("~/Documents/NetworkDrives", "Documents Network Drives")
        ]
        
        Task {
            var points: [SetupMountPointInfo] = []
            for (path, name) in defaultPaths {
                let expandedPath = NSString(string: path).expandingTildeInPath
                let isGranted = await bookmarkManager.hasBookmark(for: expandedPath)
                
                points.append(SetupMountPointInfo(
                    path: expandedPath,
                    displayName: name,
                    isGranted: isGranted
                ))
            }
            await MainActor.run {
                commonMountPoints = points
            }
        }
    }
    
    private func loadExistingServers() {
        do {
            existingServers = try serverRepository.fetchAll()
        } catch {
            existingServers = []
            print("Failed to load existing servers: \(error)")
        }
    }
}

// MARK: - Supporting Types

enum SetupStep: Int, CaseIterable, Identifiable {
    case welcome
    case permissions
    case migration
    case complete
    
    var id: Int { rawValue }
}

struct SetupMountPointInfo {
    let path: String
    let displayName: String
    var isGranted: Bool
}

struct SetupMigrationResult {
    let server: ServerConfiguration
    var status: MigrationStatus
}

enum MigrationStatus {
    case pending
    case success
    case needsPermission
    case failed(String)
    
    var icon: String {
        switch self {
        case .pending:
            return "clock"
        case .success:
            return "checkmark.circle.fill"
        case .needsPermission:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .pending:
            return .secondary
        case .success:
            return .green
        case .needsPermission:
            return .orange
        case .failed:
            return .red
        }
    }
    
    var description: String {
        switch self {
        case .pending:
            return "Pending"
        case .success:
            return "Migrated"
        case .needsPermission:
            return "Needs permission"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
}