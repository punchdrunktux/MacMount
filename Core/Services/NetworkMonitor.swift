//
//  NetworkMonitor.swift
//  MacMount
//
//  Monitors network connectivity and quality
//

import Network
import Combine
import OSLog

actor NetworkMonitor: ObservableObject {
    // Published properties for UI binding
    @Published private(set) var isConnected = false
    @Published private(set) var connectionType: NWInterface.InterfaceType?
    @Published private(set) var isExpensive = false
    @Published private(set) var isConstrained = false
    @Published private(set) var currentInterface: String?
    
    // Network monitoring
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.monitor", qos: .utility)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "Network")
    
    // Publishers
    private let networkChangeSubject = PassthroughSubject<NetworkConnectionStatus, Never>()
    var networkChangePublisher: AnyPublisher<NetworkConnectionStatus, Never> {
        networkChangeSubject.eraseToAnyPublisher()
    }
    
    init() {
        Task {
            await startMonitoring()
        }
    }
    
    deinit {
        monitor.cancel()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                await self?.updatePath(path)
            }
        }
        
        monitor.start(queue: queue)
        
        // Get initial network state
        let currentPath = monitor.currentPath
        Task {
            await updatePath(currentPath)
        }
        
        logger.info("Network monitoring started")
    }
    
    private func updatePath(_ path: NWPath) async {
        let previouslyConnected = isConnected
        
        // Update connection status
        self.isConnected = path.status == .satisfied
        self.isExpensive = path.isExpensive
        self.isConstrained = path.isConstrained
        
        // Determine primary interface
        if let interface = path.availableInterfaces.first {
            self.connectionType = interface.type
            self.currentInterface = interface.name
        } else {
            self.connectionType = nil
            self.currentInterface = nil
        }
        
        // Log status changes
        if previouslyConnected != isConnected {
            if isConnected {
                logger.info("Network connected via \(self.connectionType?.description ?? "unknown")")
            } else {
                logger.warning("Network disconnected")
            }
            
            // Post notification for network status change
            NotificationCenter.default.post(name: Notification.Name("NetworkStatusChanged"), object: nil)
        }
        
        // Publish network change event
        let status = NetworkConnectionStatus(
            isConnected: isConnected,
            connectionType: connectionType,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
        networkChangeSubject.send(status)
    }
    
    // Public methods
    func checkConnectivity() -> NetworkConnectionStatus {
        NetworkConnectionStatus(
            isConnected: isConnected,
            connectionType: connectionType,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
    }
    
    func isReachable(host: String, port: Int? = nil, timeout: TimeInterval = 5) async -> Bool {
        logger.debug("Testing reachability for \(host):\(port ?? 80) with \(timeout)s timeout")
        
        return await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: UInt16(port ?? 80))!
            )
            
            let connection = NWConnection(to: endpoint, using: .tcp)
            var hasResumed = false
            let resumeLock = NSLock()
            
            func resumeOnce(with value: Bool) {
                resumeLock.lock()
                defer { resumeLock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: value)
            }
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    self.logger.debug("Connection to \(host):\(port ?? 80) successful")
                    connection.cancel()
                    resumeOnce(with: true)
                case .failed(let error):
                    self.logger.debug("Connection to \(host):\(port ?? 80) failed: \(error)")
                    connection.cancel()
                    resumeOnce(with: false)
                case .waiting(let error):
                    self.logger.debug("Connection to \(host):\(port ?? 80) waiting: \(error)")
                default:
                    break
                }
            }
            
            let timeoutQueue = DispatchQueue(label: "reachability.timeout")
            timeoutQueue.asyncAfter(deadline: .now() + timeout) {
                self.logger.debug("Connection to \(host):\(port ?? 80) timed out after \(timeout)s")
                connection.cancel()
                resumeOnce(with: false)
            }
            
            connection.start(queue: queue)
        }
    }
}

// MARK: - Supporting Types

struct NetworkConnectionStatus {
    let isConnected: Bool
    let connectionType: NWInterface.InterfaceType?
    let isExpensive: Bool
    let isConstrained: Bool
    
    var description: String {
        if !isConnected {
            return "Disconnected"
        }
        
        var desc = connectionType?.description ?? "Unknown"
        if isExpensive {
            desc += " (Expensive)"
        }
        if isConstrained {
            desc += " (Constrained)"
        }
        return desc
    }
}

// MARK: - Extensions

extension NWInterface.InterfaceType {
    var description: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "Cellular"
        case .wiredEthernet:
            return "Ethernet"
        case .loopback:
            return "Loopback"
        case .other:
            return "Other"
        @unknown default:
            return "Unknown"
        }
    }
}