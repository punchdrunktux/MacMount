//
//  MacMountTests.swift
//  MacMountTests
//
//  Unit tests for MacMount
//

import XCTest
@testable import MacMount

final class MacMountTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - Model Tests
    
    func testServerConfigurationCreation() throws {
        let config = ServerConfiguration(
            name: "Test Server",
            protocol: .smb,
            serverAddress: "192.168.1.100",
            shareName: "TestShare",
            username: "testuser"
        )
        
        XCTAssertEqual(config.name, "Test Server")
        XCTAssertEqual(config.protocol, .smb)
        XCTAssertEqual(config.serverAddress, "192.168.1.100")
        XCTAssertEqual(config.shareName, "TestShare")
        XCTAssertEqual(config.username, "testuser")
        XCTAssertEqual(config.displayName, "Test Server")
        XCTAssertEqual(config.mountURL, "smb://testuser@192.168.1.100/TestShare")
    }
    
    func testServerConfigurationDisplayName() throws {
        let configWithName = ServerConfiguration(
            name: "My Server",
            protocol: .afp,
            serverAddress: "server.local",
            shareName: "Share"
        )
        XCTAssertEqual(configWithName.displayName, "My Server")
        
        let configWithoutName = ServerConfiguration(
            name: "",
            protocol: .afp,
            serverAddress: "server.local",
            shareName: "Share"
        )
        XCTAssertEqual(configWithoutName.displayName, "server.local/Share")
    }
    
    func testNetworkProtocolProperties() throws {
        XCTAssertEqual(NetworkProtocol.smb.defaultPort, 445)
        XCTAssertEqual(NetworkProtocol.afp.defaultPort, 548)
        XCTAssertEqual(NetworkProtocol.nfs.defaultPort, 2049)
        
        XCTAssertTrue(NetworkProtocol.smb.requiresAuthentication)
        XCTAssertTrue(NetworkProtocol.afp.requiresAuthentication)
        XCTAssertFalse(NetworkProtocol.nfs.requiresAuthentication)
    }
    
    func testMountStateTransitions() throws {
        XCTAssertFalse(MountState.unmounted.isMounted)
        XCTAssertTrue(MountState.mounted.isMounted)
        XCTAssertFalse(MountState.mounting.isMounted)
        XCTAssertTrue(MountState.stale.isMounted)
        
        XCTAssertTrue(MountState.mounting.isTransitioning)
        XCTAssertTrue(MountState.unmounting.isTransitioning)
        XCTAssertFalse(MountState.mounted.isTransitioning)
    }
    
    // MARK: - Persistence Tests
    
    func testUserDefaultsRepository() async throws {
        let repository = UserDefaultsServerRepository()
        
        // Clear any existing data
        repository.deleteAll()
        
        // Test adding a server
        let server = ServerConfiguration(
            name: "Test Server",
            protocol: .smb,
            serverAddress: "192.168.1.100",
            shareName: "TestShare"
        )
        
        try repository.save(server)
        
        // Test fetching
        let servers = repository.fetchAll()
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers.first?.id, server.id)
        
        // Test updating
        var updatedServer = server
        updatedServer.name = "Updated Server"
        try repository.save(updatedServer)
        
        let updatedServers = repository.fetchAll()
        XCTAssertEqual(updatedServers.count, 1)
        XCTAssertEqual(updatedServers.first?.name, "Updated Server")
        
        // Test deletion
        try repository.delete(server.id)
        let remainingServers = repository.fetchAll()
        XCTAssertEqual(remainingServers.count, 0)
    }
    
    // MARK: - Coordinator Tests
    
    func testRetryManagerCircuitBreaker() async throws {
        let retryManager = RetryManager()
        let serverId = UUID()
        
        // Should allow retries initially
        let shouldRetry1 = await retryManager.shouldRetry(for: serverId)
        XCTAssertTrue(shouldRetry1)
        
        // Record failures
        for _ in 0..<5 {
            await retryManager.recordFailure(for: serverId)
        }
        
        // Should not allow retries after max failures
        let shouldRetry2 = await retryManager.shouldRetry(for: serverId)
        XCTAssertFalse(shouldRetry2)
        
        // Success should reset
        await retryManager.recordSuccess(for: serverId)
        let shouldRetry3 = await retryManager.shouldRetry(for: serverId)
        XCTAssertTrue(shouldRetry3)
    }
    
    func testRetryDelayCalculation() async throws {
        let retryManager = RetryManager()
        let serverId = UUID()
        let strategy = RetryStrategy.normal
        
        // First retry should have base delay
        await retryManager.recordFailure(for: serverId)
        let delay1 = await retryManager.nextRetryDelay(for: serverId, strategy: strategy)
        XCTAssertNotNil(delay1)
        XCTAssertGreaterThan(delay1!, 0)
        
        // Subsequent retries should have exponential backoff
        await retryManager.recordFailure(for: serverId)
        let delay2 = await retryManager.nextRetryDelay(for: serverId, strategy: strategy)
        XCTAssertNotNil(delay2)
        XCTAssertGreaterThan(delay2!, delay1!)
    }
    
    // MARK: - Credential Manager Tests
    
    func testCredentialSerialization() throws {
        let credential = NetworkCredential(
            server: "test.server.com",
            username: "testuser",
            password: "testpass",
            protocol: .smb
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(credential)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NetworkCredential.self, from: data)
        
        XCTAssertEqual(decoded.server, credential.server)
        XCTAssertEqual(decoded.username, credential.username)
        XCTAssertEqual(decoded.password, credential.password)
        XCTAssertEqual(decoded.protocol, credential.protocol)
    }
    
    // MARK: - Error Tests
    
    func testMountErrorDescriptions() {
        let authError = MountError.authenticationFailed
        XCTAssertEqual(authError.errorDescription, "Authentication failed. Please check your username and password.")
        
        let networkError = MountError.networkUnavailable
        XCTAssertEqual(networkError.errorDescription, "Network is not available")
        
        let mountError = MountError.mountFailed(errno: 1)
        XCTAssertTrue(mountError.errorDescription?.contains("Mount operation failed") ?? false)
    }
    
    func testMountErrorRecoverySuggestions() {
        let vpnError = MountError.vpnRequired
        XCTAssertNotNil(vpnError.recoverySuggestion)
        XCTAssertTrue(vpnError.recoverySuggestion?.contains("VPN") ?? false)
        
        let timeoutError = MountError.timeoutExceeded
        XCTAssertNotNil(timeoutError.recoverySuggestion)
    }
}

// MARK: - Mock Helpers

class MockServerRepository: ServerRepositoryProtocol {
    private var servers: [ServerConfiguration] = []
    
    func save(_ server: ServerConfiguration) throws {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
    }
    
    func fetchAll() -> [ServerConfiguration] {
        return servers
    }
    
    func delete(_ id: UUID) throws {
        servers.removeAll { $0.id == id }
    }
    
    func deleteAll() {
        servers.removeAll()
    }
}