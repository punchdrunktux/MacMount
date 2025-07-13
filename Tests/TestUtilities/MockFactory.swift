//
//  MockFactory.swift
//  MacMountTests
//
//  Factory methods for creating common test objects and mocks
//

import Foundation
@testable import MacMount

enum MockFactory {
    
    // MARK: - Server Configurations
    
    static func makeServerConfiguration(
        name: String = "Test Server",
        protocol: NetworkProtocol = .smb,
        serverAddress: String = "192.168.1.100",
        shareName: String = "TestShare",
        username: String? = "testuser",
        mountPoint: String? = nil,
        requiresVPN: Bool = false,
        autoMount: Bool = true
    ) -> ServerConfiguration {
        var config = ServerConfiguration(
            name: name,
            protocol: `protocol`,
            serverAddress: serverAddress,
            shareName: shareName,
            username: username,
            mountPoint: mountPoint
        )
        config.requiresVPN = requiresVPN
        config.autoMount = autoMount
        return config
    }
    
    static func makeSMBServer(name: String = "SMB Server") -> ServerConfiguration {
        makeServerConfiguration(name: name, protocol: .smb)
    }
    
    static func makeAFPServer(name: String = "AFP Server") -> ServerConfiguration {
        makeServerConfiguration(name: name, protocol: .afp, serverAddress: "afp.local")
    }
    
    static func makeNFSServer(name: String = "NFS Server") -> ServerConfiguration {
        makeServerConfiguration(
            name: name, 
            protocol: .nfs, 
            serverAddress: "nfs.local",
            username: nil  // NFS doesn't require auth
        )
    }
    
    // MARK: - Credentials
    
    static func makeCredential(
        server: String = "test.server.com",
        username: String = "testuser",
        password: String = "testpass",
        protocol: NetworkProtocol = .smb
    ) -> NetworkCredential {
        NetworkCredential(
            server: server,
            username: username,
            password: password,
            protocol: `protocol`
        )
    }
    
    // MARK: - Mount Results
    
    static func makeMountResult(
        success: Bool = true,
        mountPoint: String? = "/Volumes/TestShare",
        error: MountError? = nil
    ) -> MountResult {
        MountResult(
            success: success,
            mountPoint: mountPoint,
            error: error
        )
    }
    
    // MARK: - Mount Options
    
    static func makeMountOptions(
        readOnly: Bool = false,
        nobrowse: Bool = true,
        timeout: Int = 10,
        retryCount: Int = 3,
        forceOverwrite: Bool = false
    ) -> MountOptions {
        MountOptions(
            readOnly: readOnly,
            nobrowse: nobrowse,
            timeout: timeout,
            retryCount: retryCount,
            forceOverwrite: forceOverwrite
        )
    }
    
    // MARK: - Connection Log Entries
    
    static func makeConnectionLogEntry(
        server: ServerConfiguration? = nil,
        timestamp: Date = Date(),
        event: ConnectionEvent = .mountAttempt,
        success: Bool = true,
        details: String? = nil,
        error: String? = nil
    ) -> ConnectionLogEntry {
        ConnectionLogEntry(
            serverId: server?.id ?? UUID(),
            serverName: server?.displayName ?? "Test Server",
            timestamp: timestamp,
            event: event,
            success: success,
            details: details,
            error: error
        )
    }
}

// MARK: - Test Constants

enum TestConstants {
    static let testTimeout: TimeInterval = 5.0
    static let testMountPoint = "/Volumes/TestShare"
    static let testServerAddress = "192.168.1.100"
    static let testShareName = "TestShare"
    static let testUsername = "testuser"
    static let testPassword = "testpass123"
    
    static let sampleServers = [
        MockFactory.makeSMBServer(name: "Office FileServer"),
        MockFactory.makeAFPServer(name: "Time Machine Backup"),
        MockFactory.makeNFSServer(name: "Development Server")
    ]
}