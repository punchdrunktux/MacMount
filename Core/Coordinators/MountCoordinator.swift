//
//  MountCoordinator.swift
//  MacMount
//
//  Central coordinator for mount operations
//

import Foundation
import Combine
import OSLog
import AppKit

protocol Coordinator {
    func start() async
    func stop() async
}

/// Events that can trigger server evaluation
enum EvaluationEvent {
    case healthCheck
    case networkChange
    case vpnChange
    case systemWake
    case userInitiated
    case startup
    
    var description: String {
        switch self {
        case .healthCheck: return "Health Check"
        case .networkChange: return "Network Change"
        case .vpnChange: return "VPN Change"
        case .systemWake: return "System Wake"
        case .userInitiated: return "User Action"
        case .startup: return "App Startup"
        }
    }
    
    /// Delay before evaluation (allows for event coalescing)
    var evaluationDelay: TimeInterval {
        switch self {
        case .healthCheck: return 0.1 // Small delay to allow state updates
        case .networkChange: return 2.0 // Wait for network to stabilize
        case .vpnChange: return 1.0 // Wait for VPN routes
        case .systemWake: return 3.0 // Wait for system to stabilize
        case .userInitiated: return 0.0 // Immediate
        case .startup: return 0.5 // Brief delay for initialization
        }
    }
}

actor MountCoordinator: Coordinator {
    static let shared = MountCoordinator()
    
    private var mountService: MountService!
    private let networkMonitor = NetworkMonitor()
    private let vpnMonitor = VPNMonitor()
    private let retryManager = RetryManager()
    private let configRepository = UserDefaultsServerRepository()
    private let bookmarkManager: BookmarkManager
    
    init(bookmarkManager: BookmarkManager = BookmarkManager()) {
        self.bookmarkManager = bookmarkManager
    }
    
    private var mountStates: [UUID: MountState] = [:]
    private var mountTasks: [UUID: Task<Void, Never>] = [:]
    private var mountStartTimes: [UUID: Date] = [:] // Track when mount operations started
    private var healthCheckFailures: [UUID: Int] = [:] // Track consecutive health check failures
    private var lastSuccessfulMounts: [UUID: Date] = [:] // Track when mounts last succeeded
    private var stateObservers: [(([UUID: MountState]) async -> Void)] = []
    private var healthCheckTask: Task<Void, Never>?
    
    // Event-driven evaluation infrastructure
    private var serverEvaluationQueues: [UUID: Task<Void, Never>] = [:]
    
    // Track user-initiated disconnects with timestamp
    private var temporarilyDisconnectedServers: [UUID: Date] = [:]
    private let temporaryDisconnectDuration: TimeInterval = 300 // 5 minutes
    
    // Network change debouncing
    private let networkChangeDebouncer = Debouncer(delay: 3.0) // 3 seconds
    private let stateUpdateDebouncer = Debouncer(delay: 0.1) // 100ms for rapid state updates
    
    private var isRunning = false
    private let normalHealthCheckInterval: TimeInterval = 30.0
    private let recoveryHealthCheckInterval: TimeInterval = 20.0
    
    private var healthCheckInterval: TimeInterval {
        // Count unmounted/errored servers
        let problemCount = mountStates.values.filter { state in
            switch state {
            case .unmounted, .error, .stale:
                return true
            case .mounted(.stale): // Mounted but stale needs recovery
                return true
            case .mounted(.connected), .mounted(.degraded), .mounted(.validating), .mounting, .unmounting, .disabled:
                return false
            }
        }.count
        
        // Use faster interval if any servers need recovery
        return problemCount > 0 ? recoveryHealthCheckInterval : normalHealthCheckInterval
    }
    
    // MARK: - Lifecycle
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        
        // Initialize mount service with shared bookmark manager
        mountService = MountService(bookmarkManager: bookmarkManager)
        
        Logger.system.info("MountCoordinator started")
        
        // Start monitoring network and VPN
        await startMonitoring()
        
        // Start periodic health checks
        startHealthCheckTimer()
        
        // Wait for VPN monitor to complete initialization
        Logger.system.info("Waiting for VPN monitor initialization...")
        await vpnMonitor.waitForInitialization()
        
        // Initial evaluation of all servers
        Logger.system.info("Starting initial server evaluation...")
        await evaluateAllServers(event: .startup)
    }
    
    // MARK: - Public Methods for Management State Control
    func setManagementState(for id: UUID, state: ManagementState) async {
        do {
            let servers = try configRepository.fetchAll()
            guard var config = servers.first(where: { $0.id == id }) else { return }
            
            config.managementState = state
            try configRepository.save(config)
            
            Logger.mount.info("Set management state for server \(id) to \(state.rawValue)")
            
            // If disabling, unmount immediately and set disabled state
            if state == .disabled {
                await unmountServer(id: id)
                await updateMountState(for: id, state: .disabled)
            } else {
                // If enabling, reset to unmounted state first, then schedule evaluation
                await updateMountState(for: id, state: .unmounted)
                await scheduleEvaluation(for: config.id, event: .userInitiated)
            }
        } catch {
            Logger.mount.error("Failed to update management state: \(error)")
        }
    }
    
    // MARK: - Event-Driven Evaluation Infrastructure
    
    /// Schedules evaluation for a single server, automatically coalescing rapid events
    func scheduleEvaluation(for serverId: UUID, event: EvaluationEvent) async {
        // Cancel any existing evaluation for this server (automatic event coalescing)
        serverEvaluationQueues[serverId]?.cancel()
        
        Logger.system.debug("🗓️ Scheduled evaluation for server \(serverId) due to \(event.description) (delay: \(event.evaluationDelay)s)")
        
        // Create new evaluation task with event-specific delay
        serverEvaluationQueues[serverId] = Task { [weak self] in
            // Wait for event-specific delay (allows for stabilization and coalescing)
            if event.evaluationDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(event.evaluationDelay * 1_000_000_000))
            }
            
            // Check if task was cancelled during delay
            guard !Task.isCancelled else { return }
            
            await self?.performSingleEvaluation(for: serverId, triggeredBy: event)
        }
    }
    
    /// Schedules evaluation for all enabled servers
    func scheduleEvaluationForAllServers(event: EvaluationEvent) async {
        do {
            let servers = try configRepository.fetchAll()
            let enabledServers = servers.filter { $0.managementState == .enabled }
            
            Logger.system.info("🗓️ Scheduled evaluation for \(enabledServers.count) enabled servers due to \(event.description)")
            
            for server in enabledServers {
                await scheduleEvaluation(for: server.id, event: event)
            }
        } catch {
            Logger.system.error("Failed to schedule evaluation for all servers: \(error)")
        }
    }
    
    /// Performs evaluation for a single server with event context
    private func performSingleEvaluation(for serverId: UUID, triggeredBy event: EvaluationEvent) async {
        do {
            let servers = try configRepository.fetchAll()
            guard let config = servers.first(where: { $0.id == serverId }) else {
                Logger.system.warning("Server \(serverId) not found during evaluation")
                return
            }
            
            // Skip disabled servers unless it's a user-initiated event
            guard config.managementState == .enabled || event == .userInitiated else {
                Logger.system.debug("Skipping evaluation for disabled server \(config.displayName)")
                return
            }
            
            Logger.system.info("🔍 Evaluating \(config.displayName) (triggered by \(event.description))")
            
            // Remove from evaluation queue since we're starting evaluation
            serverEvaluationQueues.removeValue(forKey: serverId)
            
            // Perform the actual evaluation (reuse existing logic)
            await evaluateServerInternal(config, triggeredBy: event)
            
        } catch {
            Logger.system.error("Failed to evaluate server \(serverId): \(error)")
        }
    }
    
    func stop() async {
        guard isRunning else { return }
        isRunning = false
        
        // Cancel health check timer
        healthCheckTask?.cancel()
        healthCheckTask = nil
        
        // Cancel all evaluation queues
        for task in serverEvaluationQueues.values {
            task.cancel()
        }
        serverEvaluationQueues.removeAll()
        
        // Cancel network change debounce
        await networkChangeDebouncer.cancel()
        await stateUpdateDebouncer.cancel()
        
        // Cancel all mount tasks
        for task in mountTasks.values {
            task.cancel()
        }
        mountTasks.removeAll()
        
        // Clear health check failure tracking
        healthCheckFailures.removeAll()
        lastSuccessfulMounts.removeAll()
        
        Logger.system.info("MountCoordinator stopped")
    }
    
    // MARK: - Public Methods
    func evaluateAllServers(event: EvaluationEvent = .startup) async {
        await scheduleEvaluationForAllServers(event: event)
    }
    
    private func evaluateServerInternal(_ config: ServerConfiguration, triggeredBy event: EvaluationEvent) async {
        Logger.system.info("=== Evaluating server \(config.displayName) ===")
        Logger.system.info("Server address: \(config.serverAddress), requiresVPN: \(config.requiresVPN)")
        
        // Note: Server management state filtering is done in performSingleEvaluation
        
        // Check if temporarily disconnected by user
        if let disconnectTime = temporarilyDisconnectedServers[config.id] {
            let timeSinceDisconnect = Date().timeIntervalSince(disconnectTime)
            if timeSinceDisconnect < temporaryDisconnectDuration {
                Logger.system.info("Skipping \(config.displayName) - user disconnected \(Int(timeSinceDisconnect))s ago")
                return
            } else {
                // Timeout expired, remove from temporary list
                temporarilyDisconnectedServers.removeValue(forKey: config.id)
                Logger.system.info("Temporary disconnect expired for \(config.displayName)")
            }
        }
        
        // First check if mount exists on filesystem via MountService
        let isMountedOnFS = await mountService.isMounted(config.id)
        if isMountedOnFS {
            // Mount exists - check network reachability before setting state
            Logger.system.info("Server \(config.displayName) is already mounted on filesystem")
            
            // Check network connectivity to determine appropriate state
            let port = config.protocol.defaultPort
            let isNetworkReachable = await networkMonitor.isReachable(host: config.serverAddress, port: port, timeout: 3)
            
            if isNetworkReachable {
                await updateMountState(for: config.id, state: .mountedConnected())
                Logger.system.debug("Server \(config.displayName) mount is healthy - no action needed")
                return
            } else {
                // Mount exists but server unreachable - degraded state
                Logger.system.info("Server \(config.displayName) mounted but unreachable - marking as degraded")
                await updateMountState(for: config.id, state: .mountedDegraded())
                return
            }
        }
        
        // Check our internal state tracking and detect stuck operations
        if let currentState = mountStates[config.id] {
            switch currentState {
            case .mounted:
                if !isMountedOnFS {
                    // Our state says mounted but filesystem check said no - state is out of sync
                    Logger.system.warning("State mismatch for \(config.displayName) - internal state: mounted, filesystem: unmounted")
                    await updateMountState(for: config.id, state: .unmounted)
                }
            case .mounting:
                // Check for stuck mounting operations
                if let startTime = mountStartTimes[config.id] {
                    let mountDuration = Date().timeIntervalSince(startTime)
                    let maxMountDuration: TimeInterval = 120 // 2 minutes maximum for mount operations
                    
                    if mountDuration > maxMountDuration {
                        Logger.system.warning("Mount operation for \(config.displayName) has been running for \(Int(mountDuration))s (exceeds \(Int(maxMountDuration))s limit) - canceling and resetting")
                        
                        // Cancel the stuck mount task
                        mountTasks[config.id]?.cancel()
                        mountTasks.removeValue(forKey: config.id)
                        mountStartTimes.removeValue(forKey: config.id)
                        
                        // Reset state to unmounted
                        await updateMountState(for: config.id, state: .unmounted)
                        
                        await MainActor.run {
                            ConnectionLogger.shared.logInfo(server: config, message: "⚠️ Mount operation timed out after \(Int(mountDuration))s - operation canceled and reset")
                        }
                    } else {
                        Logger.system.info("Mount operation for \(config.displayName) in progress for \(Int(mountDuration))s - allowing to continue")
                        return // Don't interfere with ongoing mount
                    }
                } else {
                    // Mounting state but no start time tracked - this shouldn't happen
                    Logger.system.warning("Mount state is 'mounting' but no start time tracked for \(config.displayName) - resetting to unmounted")
                    await updateMountState(for: config.id, state: .unmounted)
                }
            case .unmounting:
                // Check for stuck unmounting operations  
                if let startTime = mountStartTimes[config.id] {
                    let unmountDuration = Date().timeIntervalSince(startTime)
                    let maxUnmountDuration: TimeInterval = 60 // 1 minute maximum for unmount operations
                    
                    if unmountDuration > maxUnmountDuration {
                        Logger.system.warning("Unmount operation for \(config.displayName) has been running for \(Int(unmountDuration))s (exceeds \(Int(maxUnmountDuration))s limit) - resetting state")
                        
                        mountStartTimes.removeValue(forKey: config.id)
                        
                        // Check actual filesystem state to determine correct state
                        let actuallyMounted = await mountService.isMounted(config.id)
                        await updateMountState(for: config.id, state: actuallyMounted ? .mountedConnected() : .unmounted)
                        
                        await MainActor.run {
                            ConnectionLogger.shared.logInfo(server: config, message: "⚠️ Unmount operation timed out after \(Int(unmountDuration))s - state synchronized with filesystem")
                        }
                    } else {
                        Logger.system.info("Unmount operation for \(config.displayName) in progress for \(Int(unmountDuration))s - allowing to continue")
                        return // Don't interfere with ongoing unmount
                    }
                } else {
                    // Unmounting state but no start time tracked
                    Logger.system.warning("Mount state is 'unmounting' but no start time tracked for \(config.displayName) - synchronizing with filesystem")
                    let actuallyMounted = await mountService.isMounted(config.id)
                    await updateMountState(for: config.id, state: actuallyMounted ? .mountedConnected() : .unmounted)
                }
            default:
                break
            }
        }
        
        // Check if conditions are met for mounting
        let networkAvailable = await networkMonitor.isConnected
        Logger.system.info("Network available: \(networkAvailable)")
        
        // For VPN-required servers, use route-based checking
        var vpnAccessible = true
        if config.requiresVPN {
            Logger.system.info("Server \(config.displayName) requires VPN, performing route check...")
            
            // For better reliability, check route twice with a small delay for WireGuard
            vpnAccessible = await vpnMonitor.isServerAccessibleViaVPN(config.serverAddress)
            
            // If not accessible, wait briefly and check once more (WireGuard routes can be slow to update)
            if !vpnAccessible {
                Logger.system.info("First VPN route check failed, retrying in 1 second...")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                vpnAccessible = await vpnMonitor.isServerAccessibleViaVPN(config.serverAddress)
            }
            
            Logger.system.info("Server \(config.displayName) VPN accessibility final result: \(vpnAccessible)")
        }
        
        Logger.system.info("Final evaluation for \(config.displayName): network=\(networkAvailable), requiresVPN=\(config.requiresVPN), vpnAccessible=\(vpnAccessible)")
        
        let shouldMount = networkAvailable && vpnAccessible
        
        if shouldMount {
            Logger.system.info("Attempting to mount \(config.displayName)")
            await attemptMount(config)
        } else {
            Logger.system.info("Not mounting \(config.displayName) - conditions not met")
            await updateMountState(for: config.id, state: .unmounted)
        }
    }
    
    func mountServer(_ config: ServerConfiguration) async {
        // Clear any temporary disconnect when user manually mounts
        temporarilyDisconnectedServers.removeValue(forKey: config.id)
        
        // Enable server when user manually mounts
        if config.managementState == .disabled {
            await setManagementState(for: config.id, state: .enabled)
        }
        await attemptMount(config)
    }
    
    func unmountServer(id: UUID, setDisabled: Bool = false, isUserInitiated: Bool = false) async {
        // If requested, disable the server
        if setDisabled {
            await setManagementState(for: id, state: .disabled)
        } else if isUserInitiated {
            // Track temporary user disconnect
            temporarilyDisconnectedServers[id] = Date()
            Logger.mount.info("User manually disconnected server \(id), will not auto-reconnect for \(self.temporaryDisconnectDuration) seconds")
        }
        
        // Cancel any ongoing mount task and clear tracking
        mountTasks[id]?.cancel()
        mountTasks.removeValue(forKey: id)
        mountStartTimes.removeValue(forKey: id) // Clear any existing operation start time
        
        // Record unmount operation start time for timeout detection
        mountStartTimes[id] = Date()
        
        // Find the configuration
        do {
            let servers = try configRepository.fetchAll()
            guard let config = servers.first(where: { $0.id == id }) else {
                return
            }
            
            // Update state
            await updateMountState(for: id, state: .unmounted)
            
            // Attempt unmount
            do {
                try await mountService.unmount(config.id)
                Logger.mount.info("Unmounted \(config.displayName)")
                await MainActor.run { 
                    ConnectionLogger.shared.logInfo(server: config, message: "Unmounted")
                }
            } catch {
                Logger.mount.error("Failed to unmount \(config.displayName): \(error)")
            }
            
            // Clear unmount operation start time (regardless of success/failure)
            mountStartTimes.removeValue(forKey: id)
        } catch {
            Logger.system.error("Failed to fetch servers: \(error)")
            // Clear unmount operation start time on error too
            mountStartTimes.removeValue(forKey: id)
        }
    }
    
    // MARK: - State Management
    func observeMountStates(_ observer: @escaping ([UUID: MountState]) async -> Void) async {
        stateObservers.append(observer)
        // Send current state immediately
        await observer(mountStates)
    }
    
    private func updateMountState(for id: UUID, state: MountState) async {
        // Validate state transition
        if let currentState = mountStates[id] {
            if !currentState.canTransition(to: state) {
                Logger.warning("Invalid state transition for server \(id): \(currentState) -> \(state)")
                return
            }
        }
        
        let oldState = mountStates[id]
        mountStates[id] = state
        
        Logger.system.debug("State transition for server \(id): \(oldState?.displayText ?? "nil") -> \(state.displayText)")
        
        // Debounce observer notifications to prevent rapid UI updates
        await stateUpdateDebouncer.debounce { [weak self] in
            guard let self = self else { return }
            
            // Notify observers with current states
            let currentStates = await self.mountStates
            for observer in await self.stateObservers {
                await observer(currentStates)
            }
        }
    }
    
    // MARK: - Monitoring
    private func startMonitoring() async {
        // Monitor network changes
        Task {
            for await _ in NotificationCenter.default.notifications(named: .init("NetworkStatusChanged")) {
                await handleNetworkChange()
            }
        }
        
        // Monitor VPN changes
        Task {
            for await _ in NotificationCenter.default.notifications(named: .NEVPNStatusDidChange) {
                await handleVPNChange()
            }
        }
        
        // Monitor system wake
        Task {
            for await _ in NotificationCenter.default.notifications(named: NSWorkspace.didWakeNotification) {
                await handleSystemWake()
            }
        }
    }
    
    private func handleNetworkChange() async {
        Logger.system.info("Network change detected, debouncing...")
        
        await networkChangeDebouncer.debounce {
            Logger.system.info("Network change debounce complete, clearing retry states and evaluating servers")
            
            // Clear all retry states on network change
            await self.retryManager.clearAllRetryStates()
            
            // Fetch servers to check management state
            do {
                let servers = try self.configRepository.fetchAll()
                let serverDict = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })
                
                // Reset error states to unmounted only for enabled servers
                for (id, state) in self.mountStates {
                    if case .error = state,
                       let server = serverDict[id],
                       server.managementState == .enabled {
                        Logger.system.info("Resetting error state for enabled server \(id) due to network change")
                        await self.updateMountState(for: id, state: .unmounted)
                    }
                }
            } catch {
                Logger.system.error("Failed to fetch servers during network change: \(error)")
            }
            
            // Re-evaluate enabled servers only
            await self.evaluateAllServers(event: .networkChange)
        }
    }
    
    private func handleVPNChange() async {
        Logger.system.info("🔄 VPN change detected, re-evaluating all servers")
        
        // Get current VPN status
        let vpnStatus = await vpnMonitor.getCurrentStatus()
        Logger.system.info("VPN status: \(vpnStatus.isConnected ? "Connected" : "Disconnected") - \(vpnStatus.protocol ?? "Unknown")")
        
        // For WireGuard, wait longer for routes to stabilize
        let isWireGuard = vpnStatus.protocol?.contains("WireGuard") ?? false
        let stabilizationDelay: UInt64 = isWireGuard ? 2_000_000_000 : 1_000_000_000 // 2s for WireGuard, 1s for others
        
        Logger.system.info("Waiting \(isWireGuard ? "2" : "1") second(s) for VPN to stabilize...")
        try? await Task.sleep(nanoseconds: stabilizationDelay)
        
        // Clear retry states to allow immediate reconnection attempts
        await retryManager.clearAllRetryStates()
        
        // If VPN disconnected, immediately unmount ALL VPN-required servers
        if !vpnStatus.isConnected {
            Logger.system.info("🔴 VPN DISCONNECTED - Proactively unmounting all VPN-required servers")
            do {
                let servers = try configRepository.fetchAll()
                let vpnRequiredServers = servers.filter { $0.requiresVPN && $0.managementState == .enabled }
                
                if vpnRequiredServers.isEmpty {
                    Logger.system.info("No enabled VPN-required servers configured")
                } else {
                    Logger.system.info("Found \(vpnRequiredServers.count) enabled VPN-required server(s) to process")
                    
                    for server in vpnRequiredServers {
                        if let currentState = mountStates[server.id] {
                            switch currentState {
                            case .mounted(_), .mounting, .stale:
                                Logger.system.info("VPN disconnected - unmounting VPN-required server '\(server.displayName)' (current state: \(String(describing: currentState)))")
                                await unmountServer(id: server.id, isUserInitiated: false)
                                await MainActor.run {
                                    ConnectionLogger.shared.logInfo(server: server, message: "🔴 VPN disconnected - automatically unmounted")
                                }
                            case .unmounted, .unmounting:
                                Logger.system.info("VPN disconnected - VPN-required server '\(server.displayName)' already unmounted/unmounting")
                            case .error:
                                Logger.system.info("VPN disconnected - VPN-required server '\(server.displayName)' already in error state")
                                // Reset to unmounted so it can be retried when VPN reconnects
                                await updateMountState(for: server.id, state: .unmounted)
                            case .disabled:
                                Logger.system.debug("VPN disconnected - VPN-required server '\(server.displayName)' is disabled, no action needed")
                            }
                        } else {
                            Logger.system.info("VPN disconnected - No state tracked for VPN-required server '\(server.displayName)'")
                            // Ensure it's marked as unmounted
                            await updateMountState(for: server.id, state: .unmounted)
                        }
                    }
                }
            } catch {
                Logger.system.error("Failed to fetch servers for VPN disconnection handling: \(error)")
            }
        } else {
            // VPN connected - validate routes and reset states for VPN-required servers
            Logger.system.info("🟢 VPN CONNECTED - Validating routes and resetting VPN-required servers")
            do {
                let servers = try configRepository.fetchAll()
                let vpnRequiredServers = servers.filter { $0.requiresVPN && $0.managementState == .enabled }
                
                if vpnRequiredServers.isEmpty {
                    Logger.system.info("No enabled VPN-required servers configured")
                } else {
                    Logger.system.info("Found \(vpnRequiredServers.count) enabled VPN-required server(s) to validate")
                    
                    // Validate routes for all VPN-required servers
                    for server in vpnRequiredServers {
                        Logger.system.info("Validating VPN route for server '\(server.displayName)' (\(server.serverAddress))")
                        let isAccessible = await vpnMonitor.isServerAccessibleViaVPN(server.serverAddress)
                        
                        if isAccessible {
                            Logger.system.info("✅ VPN route confirmed for '\(server.displayName)' - resetting state for reconnection")
                            
                            // Reset error states to allow reconnection attempts
                            if let currentState = mountStates[server.id] {
                                switch currentState {
                                case .error:
                                    await updateMountState(for: server.id, state: .unmounted)
                                    await MainActor.run {
                                        ConnectionLogger.shared.logInfo(server: server, message: "🟢 VPN connected - route validated, ready for mounting")
                                    }
                                case .mounted:
                                    Logger.system.info("Server '\(server.displayName)' already mounted and VPN route is valid")
                                default:
                                    Logger.system.info("Server '\(server.displayName)' in state \(String(describing: currentState)) with valid VPN route")
                                }
                            } else {
                                await updateMountState(for: server.id, state: .unmounted)
                            }
                        } else {
                            Logger.system.warning("❌ VPN route NOT accessible for '\(server.displayName)' despite VPN being connected")
                            await MainActor.run {
                                ConnectionLogger.shared.logInfo(server: server, message: "⚠️ VPN connected but server not accessible via VPN route")
                            }
                        }
                    }
                }
            } catch {
                Logger.system.error("Failed to validate VPN routes: \(error)")
            }
        }
        
        // Re-evaluate ALL servers with fresh route information
        Logger.system.info("🔄 Re-evaluating all servers after VPN change")
        await evaluateAllServers(event: .vpnChange)
    }
    
    private func handleSystemWake() async {
        Logger.system.info("System wake detected, re-evaluating servers")
        
        // The event-driven system will handle the delay automatically
        await evaluateAllServers(event: .systemWake)
    }
    
    // MARK: - Health Check
    private func startHealthCheckTimer() {
        healthCheckTask = Task {
            Logger.system.info("🏁 Starting health check timer")
            var checkNumber = 0
            
            while !Task.isCancelled {
                // Get current interval (dynamic based on mount states)
                let currentInterval = healthCheckInterval
                let intervalType = currentInterval == recoveryHealthCheckInterval ? "recovery" : "normal"
                Logger.system.info("⏰ Next health check in \(Int(currentInterval))s (\(intervalType) interval)")
                
                // Wait for the health check interval
                try? await Task.sleep(nanoseconds: UInt64(currentInterval * 1_000_000_000))
                
                guard !Task.isCancelled else { break }
                
                checkNumber += 1
                Logger.system.info("⏰ Health check timer fired (check #\(checkNumber))")
                
                // Check health of all servers
                await checkAllMountHealth()
            }
            Logger.system.info("🛑 Health check timer stopped")
        }
    }
    
    private func checkAllMountHealth() async {
        let startTime = Date()
        Logger.system.info("🔍 Starting health check for all servers")
        
        do {
            let servers = try configRepository.fetchAll()
            let enabledServers = servers.filter { $0.managementState != .disabled }
            
            if enabledServers.isEmpty {
                Logger.system.info("No enabled servers to check")
                return
            }
            
            // Perform health checks in parallel using TaskGroup
            let results = await withTaskGroup(of: (serverId: UUID, isStale: Bool).self) { group in
                for server in enabledServers {
                    group.addTask { [weak self] in
                        guard let self = self else { return (server.id, false) }
                        let isStale = await self.performHealthCheckForServer(server)
                        return (server.id, isStale)
                    }
                }
                
                var results: [(serverId: UUID, isStale: Bool)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            
            let checkedCount = results.count
            let staleCount = results.filter { $0.isStale }.count
            
            let totalDuration = Date().timeIntervalSince(startTime)
            Logger.system.info("🔍 Health check completed in \(String(format: "%.2f", totalDuration))s - Checked: \(checkedCount) servers, Found stale: \(staleCount)")
        } catch {
            Logger.system.error("Failed to check mount health: \(error)")
        }
    }
    
    // Perform health check for a single server - returns true if stale
    private func performHealthCheckForServer(_ server: ServerConfiguration) async -> Bool {
        let currentState = mountStates[server.id]
        
        if let state = currentState {
            switch state {
            case .mounted(let health):
                // Apply grace period only for connected mounts, not degraded ones
                if health == .connected, let lastSuccess = lastSuccessfulMounts[server.id] {
                    let timeSinceSuccess = Date().timeIntervalSince(lastSuccess)
                    if timeSinceSuccess < 60 { // 60 second grace period
                        Logger.system.debug("Skipping health check for \(server.displayName) - mount succeeded \(String(format: "%.1f", timeSinceSuccess))s ago (grace period)")
                        return false
                    }
                }
                
                Logger.system.debug("Checking health of mounted server: \(server.displayName)")
                
                // Separate filesystem and network validation
                let healthCheckStart = Date()
                
                // First check if mount still exists at filesystem level
                let mountExists = await mountService.checkMountHealth(server.id)
                
                // Then check network connectivity
                let networkCheckStart = Date()
                let port = server.protocol.defaultPort
                let isNetworkReachable = await networkMonitor.isReachable(host: server.serverAddress, port: port, timeout: 3)
                _ = Date().timeIntervalSince(networkCheckStart)
                
                let totalDuration = Date().timeIntervalSince(healthCheckStart)
                
                Logger.system.info("Health check for \(server.displayName) completed in \(String(format: "%.2f", totalDuration))s - Mount exists: \(mountExists), Network: \(isNetworkReachable ? "reachable" : "unreachable")")
                
                // Determine appropriate state based on mount and network status
                if !mountExists {
                    // Mount doesn't exist at filesystem level - definitely needs remount
                    Logger.system.warning("❌ \(server.displayName) mount no longer exists at filesystem level")
                    await MainActor.run { 
                        ConnectionLogger.shared.logInfo(server: server, message: "Mount no longer exists - will attempt to remount")
                    }
                    
                    // Mark as unmounted for immediate re-evaluation
                    await updateMountState(for: server.id, state: .unmounted)
                    return true // needs remount
                    
                } else if !isNetworkReachable {
                    // Mount exists but server is unreachable - this is a degraded state
                    Logger.system.info("⚠️ \(server.displayName) mount exists but server unreachable - marking as degraded")
                    await MainActor.run {
                        ConnectionLogger.shared.logInfo(server: server, message: "Mount exists but server unreachable (degraded state)")
                    }
                    
                    // Transition to degraded state - don't remount, just warn user
                    await updateMountState(for: server.id, state: .mountedDegraded())
                    return false // not stale, just degraded
                    
                } else {
                    // Both mount exists and network is reachable - healthy state
                    healthCheckFailures[server.id] = 0 // Reset any failure tracking
                    Logger.system.debug("✅ \(server.displayName) mount is healthy and connected")
                    
                    // Ensure we're in the connected state
                    await updateMountState(for: server.id, state: .mountedConnected())
                    return false
                }
                
            case .unmounted, .error:
                // Re-evaluate unmounted and errored servers
                Logger.system.info("Re-evaluating unmounted/errored server \(server.displayName) during health check")
                await scheduleEvaluation(for: server.id, event: .healthCheck)
                return false
                
            case .stale:
                // Stale shares should be converted to unmounted for re-evaluation
                Logger.system.info("Converting stale share \(server.displayName) to unmounted for re-evaluation")
                await MainActor.run { 
                    ConnectionLogger.shared.logInfo(server: server, message: "Converting stale share to unmounted for re-evaluation")
                }
                await updateMountState(for: server.id, state: .unmounted)
                return true // was stale
                
            case .mounting:
                // Already being mounted, skip
                Logger.system.debug("\(server.displayName) is already being mounted")
                return false
                
            case .unmounting:
                // Being unmounted, skip
                Logger.system.debug("\(server.displayName) is being unmounted")
                return false
                
            case .disabled:
                // Disabled servers should not be health checked
                Logger.system.debug("\(server.displayName) is disabled, skipping health check")
                return false
            }
        } else {
            // No state recorded, evaluate the server
            Logger.system.info("No state for \(server.displayName), evaluating")
            await scheduleEvaluation(for: server.id, event: .healthCheck)
            return false
        }
    }
    
    // MARK: - Mount Operations
    private func attemptMount(_ config: ServerConfiguration) async {
        Logger.system.info("attemptMount called for \(config.displayName)")
        
        // Check if already mounting
        if let currentState = mountStates[config.id], case .mounting = currentState {
            Logger.system.info("Mount already in progress for \(config.displayName), skipping")
            return
        }
        
        // Cancel any existing mount task
        mountTasks[config.id]?.cancel()
        
        // Record mount operation start time for timeout detection
        mountStartTimes[config.id] = Date()
        
        // Update state to mounting with initial attempt info
        await updateMountState(for: config.id, state: .mounting(attempt: 1, maxAttempts: config.retryStrategy.maxRetries))
        
        // Create new mount task
        let task = Task {
            Logger.system.info("Starting mount task for \(config.displayName)")
            await performMountWithRetry(config)
            
            // Clear start time when operation completes (success or failure)
            mountStartTimes.removeValue(forKey: config.id)
        }
        
        mountTasks[config.id] = task
    }
    
    private func performMountWithRetry(_ config: ServerConfiguration) async {
        var attemptCount = 0
        let maxAttempts = config.effectiveMaxRetries
        var lastError: MountError?
        
        while attemptCount < maxAttempts && !Task.isCancelled {
            attemptCount += 1
            
            // Log mount attempt
            let attempt = attemptCount
            let max = maxAttempts
            await MainActor.run { ConnectionLogger.shared.logMountAttempt(server: config, attempt: attempt, maxAttempts: max) }
            
            // Update state with current attempt
            await updateMountState(for: config.id, state: .mounting(attempt: attemptCount, maxAttempts: maxAttempts, lastError: lastError))
            
            do {
                // Check if we should retry
                guard await retryManager.shouldRetry(for: config.id) else {
                    let timeoutError = MountError.timeoutExceeded
                    let timeoutAttempt = attemptCount
                    await MainActor.run { ConnectionLogger.shared.logMountError(server: config, error: timeoutError, attempt: timeoutAttempt) }
                    await updateMountState(for: config.id, state: .error(timeoutError))
                    return
                }
                
                // Check network reachability
                let isReachable = await networkMonitor.isReachable(host: config.serverAddress, port: config.protocol.defaultPort)
                await MainActor.run { ConnectionLogger.shared.logNetworkCheck(server: config, reachable: isReachable) }
                
                // Attempt mount
                _ = try await mountService.mount(config)
                
                // Success
                await retryManager.recordSuccess(for: config.id)
                healthCheckFailures[config.id] = 0 // Reset health check failures on successful mount
                lastSuccessfulMounts[config.id] = Date() // Track when mount succeeded
                let successAttempt = attemptCount
                await MainActor.run { ConnectionLogger.shared.logMountSuccess(server: config, attempt: successAttempt) }
                await updateMountState(for: config.id, state: .mountedConnected())
                
                Logger.mount.info("Successfully mounted \(config.displayName) on attempt \(attemptCount)")
                return
                
            } catch {
                await retryManager.recordFailure(for: config.id)
                
                let mountError = error as? MountError ?? MountError.mountFailed(errno: -1)
                lastError = mountError
                let errorAttempt = attemptCount
                await MainActor.run { ConnectionLogger.shared.logMountError(server: config, error: mountError, attempt: errorAttempt) }
                
                // Check if this is a permanent error that shouldn't be retried
                if mountError.isAuthenticationError {
                    await updateMountState(for: config.id, state: .error(mountError))
                    Logger.mount.error("Authentication error for \(config.displayName), stopping retry: \(error)")
                    return
                }
                
                // Log the error
                Logger.mount.error("Mount attempt \(attemptCount) failed for \(config.displayName): \(error)")
                
                // If not the last attempt, wait before retrying
                if attemptCount < maxAttempts {
                    if let delay = await retryManager.nextRetryDelay(for: config.id, strategy: config.retryStrategy, customInterval: config.customRetryInterval) {
                        let retryAttempt = attemptCount
                        await MainActor.run { ConnectionLogger.shared.logRetryDelay(server: config, delay: delay, attempt: retryAttempt) }
                        
                        // Update state to show we're waiting with the error
                        await updateMountState(for: config.id, state: .mounting(attempt: attemptCount, maxAttempts: maxAttempts, lastError: lastError))
                        
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                } else {
                    // Final attempt failed
                    await updateMountState(for: config.id, state: .error(mountError))
                }
            }
        }
    }
}