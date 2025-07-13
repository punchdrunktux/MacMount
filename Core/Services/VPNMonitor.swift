//
//  VPNMonitor.swift
//  MacMount
//
//  Monitors VPN connection state
//

import Network
import NetworkExtension
import SystemConfiguration
import Combine
import OSLog

actor VPNMonitor: ObservableObject {
    @Published private(set) var isVPNConnected = false
    @Published private(set) var vpnProtocol: String?
    @Published private(set) var vpnServerAddress: String?
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "VPN")
    private var statusObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "vpn.monitor", qos: .utility)
    private var interfaceCheckTimer: Timer?
    
    // Route cache
    private var routeCache: [String: (RouteInfo, Date)] = [:]
    private let routeCacheDuration: TimeInterval = 2.0 // Further reduced cache duration for faster VPN response
    
    // Track monitored interfaces
    private var monitoredInterfaces: Set<String> = []
    
    // Publishers
    private let vpnChangeSubject = PassthroughSubject<VPNStatus, Never>()
    var vpnChangePublisher: AnyPublisher<VPNStatus, Never> {
        vpnChangeSubject.eraseToAnyPublisher()
    }
    
    private var initializationComplete = false
    
    init() {
        Task {
            await startMonitoring()
            // Perform initial checks immediately
            await checkVPNStatus()
            await checkNetworkInterfaces()
            await setInitializationComplete()
        }
    }
    
    private func setInitializationComplete() {
        initializationComplete = true
        logger.info("VPN monitor initialization complete")
    }
    
    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        interfaceCheckTimer?.invalidate()
    }
    
    private func startMonitoring() {
        // Monitor system VPN status
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { [weak self] in
                await self?.checkVPNStatus()
            }
        }
        
        // Initial check
        Task {
            await checkVPNStatus()
        }
        
        // Also monitor using Network framework
        monitorNetworkInterfaces()
        
        logger.info("VPN monitoring started")
    }
    
    private func checkVPNStatus() async {
        // Clear route cache on VPN status change
        clearRouteCache()
        
        // Check system VPN configurations
        do {
            try await NEVPNManager.shared().loadFromPreferences()
            
            let status = NEVPNManager.shared().connection.status
            let wasConnected = isVPNConnected
            
            switch status {
            case .connected:
                isVPNConnected = true
                vpnProtocol = NEVPNManager.shared().protocolConfiguration?.description
                vpnServerAddress = NEVPNManager.shared().protocolConfiguration?.serverAddress
                
                if !wasConnected {
                    logger.info("VPN connected via \(self.vpnProtocol ?? "unknown")")
                }
                
            case .connecting:
                logger.info("VPN is connecting...")
                
            case .disconnected, .disconnecting, .invalid, .reasserting:
                isVPNConnected = false
                vpnProtocol = nil
                vpnServerAddress = nil
                
                if wasConnected {
                    logger.info("VPN disconnected")
                }
                
            @unknown default:
                isVPNConnected = false
            }
            
            // Publish status change
            let vpnStatus = VPNStatus(
                isConnected: isVPNConnected,
                protocol: vpnProtocol,
                serverAddress: vpnServerAddress
            )
            vpnChangeSubject.send(vpnStatus)
            
        } catch {
            logger.error("Failed to check VPN status: \(error)")
        }
    }
    
    private func monitorNetworkInterfaces() {
        // Monitor for interface changes using SystemConfiguration
        startInterfaceChangeMonitoring()
        
        // Use a timer as a safety net (5 seconds for faster VPN change detection)
        // Primary detection is through SystemConfiguration callbacks
        queue.async { [weak self] in
            self?.interfaceCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                Task { [weak self] in
                    guard let self = self else { return }
                    
                    // Periodic check - clear route cache to ensure fresh lookups
                    await self.clearRouteCache()
                    await self.checkNetworkInterfaces()
                }
            }
            RunLoop.current.run()
        }
    }
    
    private func startInterfaceChangeMonitoring() {
        // Monitor for network configuration changes
        // This will trigger when interfaces go up/down
        let callback: @convention(c) (SCDynamicStore?, CFArray?, UnsafeMutableRawPointer?) -> Void = { _, _, info in
            guard let info = info else { return }
            let monitor = Unmanaged<VPNMonitor>.fromOpaque(info).takeUnretainedValue()
            
            Task {
                await monitor.handleInterfaceChange()
            }
        }
        
        guard let store = SCDynamicStoreCreate(nil, "MacMount.VPNMonitor" as CFString, callback, nil) else {
            logger.error("Failed to create SCDynamicStore")
            return
        }
        
        // Watch for interface and routing changes
        let keys = [
            "State:/Network/Interface/.*/Link" as CFString,
            "State:/Network/Interface/.*/IPv4" as CFString,
            "State:/Network/Global/IPv4" as CFString,
            "State:/Network/Service/.*/IPv4" as CFString,
            "State:/Network/Service/.*/DNS" as CFString
        ]
        
        SCDynamicStoreSetNotificationKeys(store, nil, keys as CFArray)
        
        let _ = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        SCDynamicStoreSetDispatchQueue(store, queue)
        
        logger.info("Started monitoring network interface changes")
    }
    
    private func handleInterfaceChange() async {
        logger.info("🔌 Network interface/routing change detected - performing immediate VPN state analysis")
        
        // Clear route cache immediately for all addresses
        clearRouteCache()
        logger.info("Route cache cleared due to interface/routing change")
        
        // Store previous state for comparison
        let wasConnected = isVPNConnected
        let previousProtocol = vpnProtocol
        let _ = monitoredInterfaces  // Keep for future use if needed
        
        // Get current network interfaces for detailed analysis
        let currentInterfaces = getNetworkInterfaces() ?? []
        let vpnInterfaces = currentInterfaces.filter { interface in
            let vpnPrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "wg"]
            return vpnPrefixes.contains { interface.lowercased().hasPrefix($0) }
        }
        
        logger.info("Interface analysis: total=\(currentInterfaces.count), VPN=\(vpnInterfaces.count), VPN interfaces: [\(vpnInterfaces.joined(separator: ", "))]")
        
        // Check interfaces immediately with detailed logging
        await checkNetworkInterfaces()
        
        // Enhanced WireGuard detection and route validation
        let hasUTunInterface = vpnInterfaces.contains { $0.hasPrefix("utun") }
        let hasOtherVPNInterface = vpnInterfaces.contains { !$0.hasPrefix("utun") }
        
        if hasUTunInterface {
            logger.info("🔍 WireGuard utun interface detected: \(vpnInterfaces.filter { $0.hasPrefix("utun") }.joined(separator: ", "))")
            
            // For WireGuard, aggressively clear route cache and force re-evaluation
            clearRouteCache()
            
            // Force VPN state update if not already detected
            if !isVPNConnected {
                self.isVPNConnected = true
                self.vpnProtocol = "WireGuard"
                logger.info("🟢 WireGuard VPN state updated via interface detection")
            }
        }
        
        if hasOtherVPNInterface {
            let otherVPNInterfaces = vpnInterfaces.filter { !$0.hasPrefix("utun") }
            logger.info("🔍 Other VPN interfaces detected: \(otherVPNInterfaces.joined(separator: ", "))")
        }
        
        // Detect VPN disconnection scenarios
        if wasConnected && !isVPNConnected {
            logger.info("🔴 VPN DISCONNECTION detected - was: \(previousProtocol ?? "unknown"), now: disconnected")
            // Clear all route cache aggressively for immediate detection
            clearRouteCache()
        }
        
        // Log state transition with detailed information
        if wasConnected != isVPNConnected {
            logger.info("🔄 VPN state CHANGED: [\(wasConnected ? "Connected" : "Disconnected")] → [\(self.isVPNConnected ? "Connected" : "Disconnected")] (Protocol: \(previousProtocol ?? "none") → \(self.vpnProtocol ?? "none"))")
        } else if vpnInterfaces.count > 0 {
            // Even if state didn't change, routes might have - particularly important for WireGuard
            logger.info("⚡ VPN interfaces present but state unchanged - routes may have changed, forcing re-evaluation")
            // Clear route cache again to ensure fresh lookups
            clearRouteCache()
        }
        
        // Always post notification to trigger server re-evaluation
        // This is critical for WireGuard reconnections where interface might not change but routes do
        await MainActor.run {
            NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: nil)
        }
        
        logger.info("Interface change handling complete - notification posted for server re-evaluation")
    }
    
    private func checkNetworkInterfaces() async {
        // Check for common VPN interfaces (including WireGuard)
        let vpnInterfaces = ["utun", "ipsec", "ppp", "tun", "tap", "wg"]
        var hasVPNInterface = false
        var detectedInterface: String?
        
        if let interfaces = getNetworkInterfaces() {
            for interface in interfaces {
                for vpnPrefix in vpnInterfaces {
                    if interface.lowercased().hasPrefix(vpnPrefix) {
                        hasVPNInterface = true
                        detectedInterface = interface
                        logger.debug("Found VPN interface: \(interface)")
                        break
                    }
                }
                if hasVPNInterface { break }
            }
        }
        
        let wasConnected = isVPNConnected
        
        // Update status based on interface detection
        if hasVPNInterface {
            if !wasConnected {
                self.isVPNConnected = true
                self.vpnProtocol = detectedInterface?.hasPrefix("utun") ?? false ? "WireGuard" : "Unknown VPN"
                logger.info("VPN connected via network interface: \(detectedInterface ?? "unknown")")
                
                let vpnStatus = VPNStatus(
                    isConnected: true,
                    protocol: self.vpnProtocol,
                    serverAddress: nil
                )
                vpnChangeSubject.send(vpnStatus)
                
                // Post notification for VPN change
                await MainActor.run {
                    NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: nil)
                }
            }
        } else if wasConnected && !hasVPNInterface {
            // VPN disconnected
            self.isVPNConnected = false
            self.vpnProtocol = nil
            logger.info("⚠️ VPN DISCONNECTED - no VPN interfaces found")
            
            // Clear route cache immediately to force re-evaluation
            clearRouteCache()
            
            let vpnStatus = VPNStatus(
                isConnected: false,
                protocol: nil,
                serverAddress: nil
            )
            vpnChangeSubject.send(vpnStatus)
            
            // Post notification for VPN change
            await MainActor.run {
                NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: nil)
            }
        } else if hasVPNInterface {
            // VPN interface exists but was already connected
            logger.debug("VPN interface still active: \(detectedInterface ?? "unknown")")
        } else {
            // No VPN interface and wasn't connected before
            logger.debug("No VPN interface detected")
        }
    }
    
    private func getNetworkInterfaces() -> [String]? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        
        var interfaces: [String] = []
        var pointer = addresses
        
        while pointer != nil {
            if let interface = pointer?.pointee {
                let name = String(cString: interface.ifa_name)
                if !interfaces.contains(name) {
                    interfaces.append(name)
                }
            }
            pointer = pointer?.pointee.ifa_next
        }
        
        return interfaces
    }
    
    // MARK: - Route-based VPN Detection
    
    private func getRouteInfo(for address: String) async -> RouteInfo? {
        // Check cache first
        if let cached = routeCache[address] {
            let (cachedInfo, timestamp) = cached
            let age = Date().timeIntervalSince(timestamp)
            if age < routeCacheDuration {
                logger.debug("Using cached route info for \(address) (age: \(Int(age))s)")
                return cachedInfo
            } else {
                logger.debug("Route cache expired for \(address) (age: \(Int(age))s)")
            }
        } else {
            logger.debug("No cached route info for \(address)")
        }
        
        do {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/sbin/route")
            task.arguments = ["-n", "get", address]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                logger.error("Failed to decode route output for \(address)")
                return nil
            }
            
            // Parse route output
            var interface: String?
            var gateway: String?
            var flags: String?
            
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("interface:") {
                    interface = trimmed.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("gateway:") {
                    gateway = trimmed.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("flags:") {
                    flags = trimmed.replacingOccurrences(of: "flags:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
            
            let routeInfo = RouteInfo(
                destination: address,
                interface: interface,
                gateway: gateway,
                flags: flags
            )
            
            // Cache the result
            routeCache[address] = (routeInfo, Date())
            
            logger.debug("Route info for \(address): interface=\(interface ?? "none"), gateway=\(gateway ?? "none"), isVPN=\(routeInfo.isVPNInterface)")
            
            return routeInfo
            
        } catch {
            logger.error("Failed to get route info for \(address): \(error)")
            return nil
        }
    }
    
    private func clearRouteCache() {
        let cacheSize = routeCache.count
        routeCache.removeAll()
        if cacheSize > 0 {
            logger.info("Route cache cleared (\(cacheSize) entries removed)")
        }
    }
    
    func forceRouteRefresh() async {
        logger.info("🔄 Forcing route cache refresh and VPN re-evaluation")
        clearRouteCache()
        
        // Check interfaces again
        await checkNetworkInterfaces()
        
        // Post notification to trigger server re-evaluation
        await MainActor.run {
            NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: nil)
        }
    }
    
    // MARK: - Public Methods
    
    func waitForInitialization() async {
        // Wait for initialization to complete
        while !initializationComplete {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        logger.info("VPN monitor ready for use")
    }
    
    func getCurrentStatus() -> VPNStatus {
        VPNStatus(
            isConnected: isVPNConnected,
            protocol: vpnProtocol,
            serverAddress: vpnServerAddress
        )
    }
    
    func isServerAccessibleViaVPN(_ serverAddress: String) async -> Bool {
        logger.info("Checking VPN accessibility for server: \(serverAddress)")
        
        // Get route information for the server
        guard let routeInfo = await getRouteInfo(for: serverAddress) else {
            logger.warning("Could not determine route for server \(serverAddress)")
            return false
        }
        
        logger.info("Route info for \(serverAddress): interface=\(routeInfo.interface ?? "none"), gateway=\(routeInfo.gateway ?? "none"), isVPN=\(routeInfo.isVPNInterface)")
        
        // Check if the route goes through a VPN interface
        if routeInfo.isVPNInterface && routeInfo.hasGateway {
            logger.info("✅ Server \(serverAddress) IS accessible via VPN interface \(routeInfo.interface ?? "unknown")")
            
            // Track this interface
            if let interface = routeInfo.interface {
                monitoredInterfaces.insert(interface)
                logger.debug("Now monitoring VPN interface: \(interface)")
            }
            
            // Update VPN status if we detected a VPN that wasn't detected before
            if !isVPNConnected {
                self.isVPNConnected = true
                self.vpnProtocol = routeInfo.interface?.hasPrefix("utun") ?? false ? "WireGuard/VPN" : "VPN"
                logger.info("VPN detected via route check for \(serverAddress)")
                
                let vpnStatus = VPNStatus(
                    isConnected: true,
                    protocol: self.vpnProtocol,
                    serverAddress: serverAddress
                )
                vpnChangeSubject.send(vpnStatus)
            }
            
            return true
        }
        
        logger.info("❌ Server \(serverAddress) is NOT accessible via VPN (interface: \(routeInfo.interface ?? "none"))")
        return false
    }
    
    func waitForVPNConnection(timeout: TimeInterval = 30) async -> Bool {
        if isVPNConnected { return true }
        
        return await withTaskGroup(of: Bool.self) { group in
            // Timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            
            // VPN monitoring task
            group.addTask { [weak self] in
                guard let self = self else { return false }
                let stream = await self.vpnChangePublisher.values
                for await status in stream {
                    if status.isConnected {
                        return true
                    }
                }
                return false
            }
            
            // Return first result (either timeout or VPN connected)
            for await result in group {
                group.cancelAll()
                return result
            }
            
            return false
        }
    }
}

// MARK: - Supporting Types

struct VPNStatus {
    let isConnected: Bool
    let `protocol`: String?
    let serverAddress: String?
    
    var description: String {
        if isConnected {
            return "\(self.protocol ?? "VPN") - \(serverAddress ?? "Connected")"
        } else {
            return "VPN Disconnected"
        }
    }
}

struct RouteInfo {
    let destination: String
    let interface: String?
    let gateway: String?
    let flags: String?
    
    var hasGateway: Bool {
        gateway != nil && gateway != "link#" && !gateway!.isEmpty
    }
    
    var isVPNInterface: Bool {
        guard let iface = interface else { return false }
        let vpnPrefixes = ["utun", "ppp", "ipsec", "tun", "tap", "wg"]
        return vpnPrefixes.contains { iface.lowercased().hasPrefix($0) }
    }
}