//
//  AppState.swift
//  MacMount
//
//  Global application state management
//

import SwiftUI
import Combine
import OSLog

@MainActor
class AppState: ObservableObject {
    @Published private(set) var servers: [ServerConfiguration] = []
    @Published private(set) var mountStates: [UUID: MountState] = [:]
    @Published private(set) var overallStatus: ConnectionStatus = .disconnected
    @Published var isLoadingServers = false
    @Published var errorMessage: String?
    
    // Performance optimization: Track mount counts to avoid O(n) calculations
    private var mountedCount = 0 // Total mounted (including degraded)
    private var healthyMountedCount = 0 // Only .mounted(.connected)
    private var mountingCount = 0
    
    private let coordinator: MountCoordinator
    private let configRepository: ServerConfigurationRepository
    let bookmarkManager: BookmarkManager
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "AppState")
    
    init(bookmarkManager: BookmarkManager = BookmarkManager(),
         coordinator: MountCoordinator? = nil,
         repository: ServerConfigurationRepository = UserDefaultsServerRepository()) {
        self.bookmarkManager = bookmarkManager
        self.coordinator = coordinator ?? MountCoordinator(bookmarkManager: bookmarkManager)
        self.configRepository = repository
        
        Task {
            await initialize()
        }
    }
    
    private func initialize() async {
        loadConfigurations()
        observeChanges()
        await coordinator.start()
    }
    
    private func loadConfigurations() {
        isLoadingServers = true
        defer { isLoadingServers = false }
        
        do {
            servers = try configRepository.fetchAll()
            logger.info("Loaded \(self.servers.count) server configurations")
        } catch {
            logger.error("Failed to load configurations: \(error)")
            errorMessage = "Failed to load server configurations"
        }
    }
    
    private func observeChanges() {
        // Start observing mount state changes from coordinator
        Task {
            await coordinator.observeMountStates { [weak self] states in
                await MainActor.run {
                    self?.updateMountStates(states)
                }
            }
        }
    }
    
    // Performance optimized state update that tracks counts incrementally
    private func updateMountStates(_ newStates: [UUID: MountState]) {
        // Create a lookup for enabled servers
        let enabledServerIds = Set(servers.filter { $0.managementState == .enabled }.map { $0.id })
        
        // Calculate deltas efficiently
        var deltaMount = 0
        var deltaHealthyMount = 0
        var deltaMounting = 0
        
        // Check removed states
        for (id, oldState) in mountStates {
            guard newStates[id] == nil else { continue }
            // Only count if server is enabled
            if enabledServerIds.contains(id) {
                if case .mounted = oldState { deltaMount -= 1 }
                if case .mounted(.connected) = oldState { deltaHealthyMount -= 1 }
                if case .mounting = oldState { deltaMounting -= 1 }
            }
        }
        
        // Check changed and new states
        for (id, newState) in newStates {
            let oldState = mountStates[id]
            
            // Skip if state hasn't changed
            if let oldState = oldState, areStatesEqual(oldState, newState) {
                continue
            }
            
            // Only count if server is enabled
            if enabledServerIds.contains(id) {
                // Update counts based on state transitions
                if let oldState = oldState {
                    if case .mounted = oldState { deltaMount -= 1 }
                    if case .mounted(.connected) = oldState { deltaHealthyMount -= 1 }
                    if case .mounting = oldState { deltaMounting -= 1 }
                }
                
                if case .mounted = newState { deltaMount += 1 }
                if case .mounted(.connected) = newState { deltaHealthyMount += 1 }
                if case .mounting = newState { deltaMounting += 1 }
            }
        }
        
        // Apply updates
        mountStates = newStates
        mountedCount += deltaMount
        healthyMountedCount += deltaHealthyMount
        mountingCount += deltaMounting
        
        // Update overall status based on cached counts
        updateOverallStatusFromCounts()
    }
    
    private func areStatesEqual(_ lhs: MountState, _ rhs: MountState) -> Bool {
        switch (lhs, rhs) {
        case (.unmounted, .unmounted),
             (.mounting, .mounting),
             (.mounted, .mounted),
             (.unmounting, .unmounting),
             (.error, .error),
             (.stale, .stale):
            return true
        default:
            return false
        }
    }
    
    // O(1) status update using cached counts
    private func updateOverallStatusFromCounts() {
        // Count only enabled servers
        let enabledCount = servers.filter { $0.managementState == .enabled }.count
        
        // If no servers are enabled, show disconnected
        if enabledCount == 0 {
            overallStatus = .disconnected
            return
        }
        
        if mountingCount > 0 {
            overallStatus = .connecting
        } else if healthyMountedCount == 0 {
            overallStatus = .disconnected
        } else if healthyMountedCount == enabledCount {
            overallStatus = .allConnected
        } else {
            overallStatus = .partiallyConnected
        }
        
        logger.debug("Status updated: \(String(describing: self.overallStatus)) (healthy: \(self.healthyMountedCount), total mounted: \(self.mountedCount)/\(enabledCount) enabled)")
    }
    
    // Legacy method for recalculating from scratch (used after config changes)
    private func recalculateCounts() {
        mountedCount = 0
        healthyMountedCount = 0
        mountingCount = 0
        
        // Create a lookup for enabled servers
        let enabledServerIds = Set(servers.filter { $0.managementState == .enabled }.map { $0.id })
        
        for (id, state) in mountStates {
            // Only count if server is enabled
            if enabledServerIds.contains(id) {
                switch state {
                case .mounted(.connected):
                    mountedCount += 1
                    healthyMountedCount += 1
                case .mounted:
                    mountedCount += 1
                case .mounting:
                    mountingCount += 1
                default:
                    break
                }
            }
        }
        
        updateOverallStatusFromCounts()
    }
    
    // MARK: - Public Methods
    
    func addServer(_ config: ServerConfiguration) async throws {
        logger.info("Adding server: \(config.displayName)")
        servers.append(config)
        try await saveConfigurationsAsync()
        recalculateCounts() // Recalculate after config change
        logger.info("Saved server configuration successfully")
        
        // Skip immediate evaluation to avoid MainActor deadlock during save
        // Server will be evaluated on next app startup or manual refresh
        // TODO: Schedule evaluation on background queue to avoid UI blocking
    }
    
    func updateServer(_ config: ServerConfiguration) async throws {
        guard let index = servers.firstIndex(where: { $0.id == config.id }) else {
            throw AppError.serverNotFound
        }
        
        servers[index] = config
        try await saveConfigurationsAsync()
        logger.info("Updated server: \(config.displayName)")
        
        // Skip immediate evaluation to avoid MainActor deadlock during save
        // Server will be evaluated on next app startup or manual refresh
        // TODO: Schedule evaluation on background queue to avoid UI blocking
    }
    
    func removeServer(_ id: UUID) async throws {
        servers.removeAll { $0.id == id }
        try await saveConfigurationsAsync()
        await coordinator.unmountServer(id: id)
        recalculateCounts() // Recalculate after config change
        logger.info("Removed server with ID: \(id)")
    }
    
    func toggleMount(for serverId: UUID) async {
        guard let server = servers.first(where: { $0.id == serverId }) else { return }
        
        if let state = mountStates[serverId], case .mounted = state {
            await coordinator.unmountServer(id: serverId)
        } else {
            await coordinator.mountServer(server)
        }
    }
    
    func mountServer(_ server: ServerConfiguration) async {
        await coordinator.mountServer(server)
    }
    
    func unmountServer(id: UUID, isUserInitiated: Bool = true) async {
        await coordinator.unmountServer(id: id, isUserInitiated: isUserInitiated)
    }
    
    func refreshAllStates() async {
        await coordinator.evaluateAllServers()
    }
    
    func stopRetrying(for serverId: UUID) async {
        // Cancel any active mount operation and disable the server
        await coordinator.unmountServer(id: serverId, setDisabled: true)
        
        // Update the mount state to indicate manual intervention needed
        await MainActor.run {
            mountStates[serverId] = .unmounted
        }
    }
    
    func toggleServerEnabled(for serverId: UUID) async {
        guard let server = servers.first(where: { $0.id == serverId }) else { return }
        
        let newState: ManagementState = server.managementState == .enabled ? .disabled : .enabled
        await coordinator.setManagementState(for: serverId, state: newState)
        
        // Reload configurations to reflect the change
        loadConfigurations()
        recalculateCounts() // Recalculate after config change
    }
    
    private func saveConfigurations() throws {
        try configRepository.saveAll(servers)
    }
    
    private func saveConfigurationsAsync() async throws {
        try await configRepository.saveAllAsync(servers)
    }
}

// MARK: - App Errors

enum AppError: LocalizedError {
    case serverNotFound
    case saveFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .serverNotFound:
            return "Server configuration not found"
        case .saveFailed(let error):
            return "Failed to save configurations: \(error.localizedDescription)"
        }
    }
}