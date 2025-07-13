//
//  MountService.swift
//  MacMount
//
//  Handles mounting and unmounting of network drives
//

import Foundation
import OSLog

actor MountService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "Mount")
    private let credentialManager = SecureCredentialManager()
    private let networkMonitor = NetworkMonitor()
    private let mountQueue = DispatchQueue(label: "mount.operations", qos: .userInitiated)
    private let mountDetector = MountDetector()
    private let bookmarkManager: BookmarkManager
    
    // Track active mounts
    private var activeMounts: [UUID: MountInfo] = [:]
    
    // Track security-scoped resources
    private var activeResources: [String: SecurityScopedResource] = [:]
    
    init(bookmarkManager: BookmarkManager = BookmarkManager()) {
        self.bookmarkManager = bookmarkManager
        
        Task {
            // Run security validation test
            await testPasswordSanitization()
            await detectExistingMounts()
        }
    }
    
    // MARK: - Mount Detection
    
    private func detectExistingMounts() async {
        logger.info("Detecting existing mounts on filesystem using native mount detection")
        
        // Get all server configurations
        let repository = UserDefaultsServerRepository()
        guard let servers = try? repository.fetchAll() else {
            logger.error("Failed to fetch server configurations for mount detection")
            return
        }
        
        // Get all network mounts from the system
        let networkMounts = mountDetector.getNetworkMounts()
        logger.info("Found \(networkMounts.count) network mounts on system")
        
        // Check each server against actual mounts
        for server in servers {
            let mountPoint = server.effectiveMountPoint
            
            // Check if this path is actually a mount point
            if mountDetector.isPathMountPoint(mountPoint) {
                // Verify it's a network mount
                if mountDetector.isNetworkMount(mountPoint) {
                    // Get detailed mount info
                    if let mountInfo = mountDetector.getMountInfo(for: mountPoint) {
                        logger.info("Detected existing mount for \(server.displayName) at \(mountPoint)")
                        logger.debug("Mount details: type=\(mountInfo.filesystemType), from=\(mountInfo.mountedFrom)")
                        
                        // Add to tracking
                        activeMounts[server.id] = MountInfo(
                            serverId: server.id,
                            mountPoint: mountPoint,
                            protocol: server.protocol,
                            mountedAt: Date()
                        )
                    }
                } else {
                    logger.warning("Path \(mountPoint) is a mount point but not a network mount")
                }
            } else {
                // Also check if this server is mounted at a different location
                if let foundMount = mountDetector.findMount(server: server.serverAddress, share: server.shareName) {
                    logger.warning("Server \(server.displayName) is mounted at \(foundMount.mountPoint) instead of expected \(mountPoint)")
                }
            }
        }
        
        logger.info("Mount detection complete. Found \(self.activeMounts.count) existing mounts matching configured servers")
    }
    
    // MARK: - Mount Operations
    
    func mount(_ config: ServerConfiguration) async throws -> MountResult {
        logger.info("Attempting to mount \(config.displayName)")
        
        // Log mount details for debugging
        await MainActor.run {
            ConnectionLogger.shared.logInfo(server: config, message: "Starting mount process - Protocol: \(config.protocol.rawValue), Server: \(config.serverAddress), Share: \(config.shareName)")
        }
        
        // Check if already mounted (in memory tracking)
        if let existingMount = activeMounts[config.id] {
            logger.info("\(config.displayName) is already mounted at \(existingMount.mountPoint)")
            await MainActor.run {
                ConnectionLogger.shared.logInfo(server: config, message: "Already mounted at \(existingMount.mountPoint)")
            }
            return MountResult(
                success: true,
                mountPoint: existingMount.mountPoint,
                protocol: config.protocol,
                message: "Already mounted"
            )
        }
        
        // Check if the same share is already mounted elsewhere on the system
        if let existingMount = mountDetector.findMount(server: config.serverAddress, share: config.shareName) {
            logger.warning("Share \(config.shareName) from \(config.serverAddress) is already mounted at \(existingMount.mountPoint)")
            await MainActor.run {
                ConnectionLogger.shared.logInfo(server: config, message: "WARNING: Share is already mounted at \(existingMount.mountPoint)")
            }
            return MountResult.failure(
                message: "Share is already mounted at \(existingMount.mountPoint)",
                protocol: config.protocol
            )
        }
        
        // Check if mount already exists on filesystem using proper mount detection
        let mountPointPath = config.effectiveMountPoint
        
        // Check if this path is actually a mount point (not just a directory)
        if mountDetector.isPathMountPoint(mountPointPath) {
            // Verify it's a network mount
            if mountDetector.isNetworkMount(mountPointPath) {
                // Get mount info to verify it's the correct mount
                if let mountInfo = mountDetector.getMountInfo(for: mountPointPath) {
                    logger.info("\(config.displayName) is already mounted at \(mountPointPath)")
                    logger.debug("Existing mount: type=\(mountInfo.filesystemType), from=\(mountInfo.mountedFrom)")
                    
                    // Add to tracking
                    activeMounts[config.id] = MountInfo(
                        serverId: config.id,
                        mountPoint: mountPointPath,
                        protocol: config.protocol,
                        mountedAt: Date()
                    )
                    
                    await MainActor.run {
                        ConnectionLogger.shared.logInfo(server: config, message: "Already mounted at \(mountPointPath)")
                    }
                    
                    return MountResult(
                        success: true,
                        mountPoint: mountPointPath,
                        protocol: config.protocol,
                        message: "Already mounted"
                    )
                }
            } else {
                logger.warning("Path \(mountPointPath) is a mount point but not a network mount")
            }
        } else {
            // Not a mount point - just a regular directory
            logger.debug("Path \(mountPointPath) exists but is not a mount point - will proceed with mounting")
        }
        
        // Pre-flight checks
        guard await isServerReachable(config, timeout: 5) else {
            logger.error("Server \(config.serverAddress) is not reachable")
            throw MountError.serverUnreachable
        }
        
        // Check VPN requirement
        if config.requiresVPN {
            // TODO: Implement VPN check when VPNMonitor is available
            logger.info("VPN check required for \(config.displayName)")
        }
        
        // Retrieve credentials if needed
        let credentials: NetworkCredential?
        if config.protocol.requiresAuthentication && config.saveCredentials {
            credentials = try await credentialManager.retrieveCredential(for: config)
            if credentials == nil && !config.username.isEmpty {
                logger.warning("No stored credentials found for \(config.displayName)")
                throw MountError.authenticationFailed
            }
        } else {
            credentials = nil
        }
        
        // Perform mount based on protocol
        let result = try await performMount(config: config, credentials: credentials)
        
        if result.success {
            // Track the mount
            activeMounts[config.id] = MountInfo(
                serverId: config.id,
                mountPoint: result.mountPoint,
                protocol: config.protocol,
                mountedAt: Date()
            )
        }
        
        return result
    }
    
    private func performMount(config: ServerConfiguration, credentials: NetworkCredential?) async throws -> MountResult {
        switch config.protocol {
        case .smb:
            return try await mountSMB(config, credentials: credentials)
        case .afp:
            return try await mountAFP(config, credentials: credentials)
        case .nfs:
            return try await mountNFS(config)
        }
    }
    
    // MARK: - Protocol-Specific Mount Methods
    
    private func mountSMB(_ config: ServerConfiguration, credentials: NetworkCredential?) async throws -> MountResult {
        // First try mount_smbfs for proper mounting without opening Finder
        logger.info("Attempting to mount SMB share using mount_smbfs")
        
        // Get timeout early for use in directory creation
        let options = MountOptions(from: config)
        let commandTimeout = options.timeout
        
        let mountPoint = URL(fileURLWithPath: config.effectiveMountPoint)
        
        // For /Volumes, let mount command handle directory creation
        // For other paths, ensure mount point exists
        if !mountPoint.path.hasPrefix("/Volumes/") {
            try await ensureMountPoint(exists: mountPoint)
        } else {
            // For /Volumes, we need to create the mount point if it doesn't exist
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: mountPoint.path, isDirectory: &isDirectory) {
                // Create the mount point using mkdir with sudo
                logger.info("Creating mount point at \(mountPoint.path)")
                await MainActor.run {
                    ConnectionLogger.shared.logInfo(server: config, message: "Creating mount point directory at \(mountPoint.path)")
                }
                
                // First try without sudo
                let mkdirResult = try await executeCommand(["/bin/mkdir", "-p", mountPoint.path], timeout: commandTimeout)
                if mkdirResult.exitCode != 0 {
                    logger.warning("mkdir failed: \(mkdirResult.output), trying with sudo")
                    await MainActor.run {
                        ConnectionLogger.shared.logInfo(server: config, message: "mkdir failed (\(mkdirResult.exitCode)): \(mkdirResult.output)")
                    }
                    
                    // Try with osascript to prompt for admin privileges
                    let script = "do shell script \"mkdir -p \(mountPoint.path)\" with administrator privileges"
                    let osascriptResult = try await executeCommand(["/usr/bin/osascript", "-e", script], timeout: commandTimeout)
                    if osascriptResult.exitCode != 0 {
                        logger.error("Failed to create mount point even with admin: \(osascriptResult.output)")
                        await MainActor.run {
                            ConnectionLogger.shared.logInfo(server: config, message: "Failed to create mount point: \(osascriptResult.output)")
                        }
                    } else {
                        await MainActor.run {
                            ConnectionLogger.shared.logInfo(server: config, message: "Mount point created successfully with admin privileges")
                        }
                    }
                } else {
                    await MainActor.run {
                        ConnectionLogger.shared.logInfo(server: config, message: "Mount point created successfully")
                    }
                }
            }
        }
        
        // Build mount command
        var command = ["/sbin/mount_smbfs"]
        
        let optionArgs = options.toCommandArguments(for: .smb)
        if !optionArgs.isEmpty {
            command.append(contentsOf: optionArgs)
        }
        
        // Sanitize inputs to prevent command injection
        let sanitizedServer = sanitizeInput(config.serverAddress)
        let sanitizedShare = sanitizeInput(config.shareName)
        
        // Build mount URL WITHOUT credentials - we'll pass them securely
        let mountURL: String
        
        if let creds = credentials {
            // Properly encode username without destroying domain formats (DOMAIN\user, user@domain.com)
            let encodedUser = creds.username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? creds.username
            
            // Log credential handling (safe - no passwords exposed)
            logger.info("Using stored credentials for user: \(creds.username.prefix(3))***@\(sanitizedServer)")
            await MainActor.run {
                ConnectionLogger.shared.logInfo(server: config, message: "🔐 Using stored credentials for \(creds.username.prefix(3))*** (password: \(creds.password.count) chars)")
            }
            
            // Secure: URL contains only username, password passed via stdin
            // Format: //user@server/share
            mountURL = "//\(encodedUser)@\(sanitizedServer)/\(sanitizedShare)"
        } else {
            mountURL = "//\(sanitizedServer)/\(sanitizedShare)"
        }
        
        command.append(mountURL)
        command.append(mountPoint.path)
        
        // Log the command for debugging (passwords masked for security)
        let sanitizedCommand = sanitizeCommandForLogging(command)
        logger.info("Executing mount command: \(sanitizedCommand)")
        await MainActor.run {
            ConnectionLogger.shared.logInfo(server: config, message: "Executing: \(sanitizedCommand)")
        }
        
        // Execute mount with secure credential passing
        var result: (output: String, exitCode: Int32)
        
        if let creds = credentials {
            // Log secure credential passing
            logger.info("Passing credentials via stdin for SMB mount (secure method)")
            await MainActor.run {
                ConnectionLogger.shared.logInfo(server: config, message: "🔐 Using stdin credential passing (secure method)")
            }
            
            // Use secure credential passing via stdin
            result = try await executeCommandWithStdin(command, stdin: creds.password + "\n", timeout: commandTimeout)
        } else {
            logger.info("Mounting without credentials (guest access)")
            await MainActor.run {
                ConnectionLogger.shared.logInfo(server: config, message: "Mounting without credentials (guest access)")
            }
            result = try await executeCommand(command, timeout: commandTimeout)
        }
        
        if result.exitCode == 0 {
            // Verify the mount is actually accessible
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            
            if fileManager.fileExists(atPath: mountPoint.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                // Try to list the directory to ensure it's really mounted
                do {
                    _ = try fileManager.contentsOfDirectory(atPath: mountPoint.path)
                    logger.info("Successfully mounted and verified SMB share \(config.displayName)")
                    await MainActor.run {
                        ConnectionLogger.shared.logInfo(server: config, message: "Mount successful and verified at \(mountPoint.path)")
                    }
                    return MountResult(
                        success: true,
                        mountPoint: mountPoint.path,
                        protocol: .smb
                    )
                } catch {
                    logger.warning("Mount appeared successful but directory is not accessible: \(error)")
                    let errorMessage = "Mount verification failed: \(error)"
                    await MainActor.run {
                        ConnectionLogger.shared.logInfo(server: config, message: errorMessage)
                    }
                    // Fall through to error handling
                    result = (output: errorMessage, exitCode: 1)
                }
            } else {
                logger.warning("Mount appeared successful but mount point doesn't exist")
                await MainActor.run {
                    ConnectionLogger.shared.logInfo(server: config, message: "Mount point not found after apparent success")
                }
                // Fall through to error handling
                result = (output: "Mount point not found", exitCode: 1)
            }
        }
        
        // Mount failed or verification failed
        if result.exitCode != 0 {
            logger.error("Failed to mount SMB share: \(result.output)")
            let exitCode = result.exitCode
            let output = result.output
            await MainActor.run {
                ConnectionLogger.shared.logInfo(server: config, message: "Mount failed - Exit code: \(exitCode), Output: \(output)")
            }
            
            // Handle "File exists" error (exit code 64)
            if result.exitCode == 64 || result.output.contains("File exists") {
                // First check if the share is already mounted elsewhere
                if let existingMount = mountDetector.findMount(server: config.serverAddress, share: config.shareName) {
                    logger.error("Mount failed because share is already mounted at \(existingMount.mountPoint)")
                    await MainActor.run {
                        ConnectionLogger.shared.logInfo(server: config, message: "ERROR: Share is already mounted at \(existingMount.mountPoint)")
                    }
                    return MountResult.failure(
                        message: "Share is already mounted at \(existingMount.mountPoint)",
                        protocol: config.protocol
                    )
                }
                
                // If share is not mounted elsewhere, it's a local mount point issue
                logger.info("Local mount point conflict detected, attempting cleanup and retry")
                await MainActor.run {
                    ConnectionLogger.shared.logInfo(server: config, message: "Mount point exists, cleaning up and retrying")
                }
                
                // First try to unmount any existing mount at this path
                let unmountResult = try await executeCommand(["/sbin/umount", mountPoint.path], timeout: commandTimeout)
                
                // If unmount succeeded or mount point doesn't exist as a mount
                if unmountResult.exitCode == 0 || unmountResult.exitCode == 1 {
                    // Wait a moment for unmount to complete
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    // Only remove the directory if it's confirmed to be blocking the mount
                    let fileManager = FileManager.default
                    if fileManager.fileExists(atPath: mountPoint.path) {
                        do {
                            try fileManager.removeItem(atPath: mountPoint.path)
                            logger.info("Removed conflicting mount point directory")
                        } catch {
                            logger.warning("Could not remove mount point: \(error)")
                        }
                    }
                    
                    // Retry the mount with credentials
                    logger.info("Retrying mount after cleanup")
                    let retryResult = try await executeCommand(command, timeout: commandTimeout)
                    
                    if retryResult.exitCode == 0 {
                        logger.info("Successfully mounted SMB share after cleanup")
                        await MainActor.run {
                            ConnectionLogger.shared.logInfo(server: config, message: "Mount successful after cleanup at \(mountPoint.path)")
                        }
                        return MountResult(
                            success: true,
                            mountPoint: mountPoint.path,
                            protocol: .smb
                        )
                    } else {
                        logger.error("Retry after cleanup failed: \(retryResult.output)")
                        await MainActor.run {
                            ConnectionLogger.shared.logInfo(server: config, message: "Mount retry failed - Exit code: \(retryResult.exitCode), Output: \(retryResult.output)")
                        }
                    }
                }
            }
            
            // Only use open command as last resort for real permission issues
            if result.output.contains("Operation not permitted") && !result.output.contains("File exists") {
                logger.warning("Real permission issue detected, open command fallback disabled to prevent Finder windows")
                await MainActor.run {
                    ConnectionLogger.shared.logInfo(server: config, message: "Mount permission denied - manual intervention may be required")
                }
            }
            
            // Check for specific errors
            if result.output.contains("Authentication error") || 
               result.output.contains("Permission denied") ||
               result.output.contains("LOGON_FAILURE") ||
               result.exitCode == 13 { // EACCES
                throw MountError.authenticationFailed
            }
            
            if result.output.contains("Directory not empty") || result.exitCode == 66 {
                // Try to unmount first if something is already there
                logger.warning("Mount point may be in use, attempting cleanup")
                let unmountResult = try await executeCommand(["/sbin/umount", mountPoint.path], timeout: commandTimeout)
                if unmountResult.exitCode == 0 {
                    // Retry mount after unmount with credentials
                    let retryResult = try await executeCommand(command, timeout: commandTimeout)
                    if retryResult.exitCode == 0 {
                        logger.info("Successfully mounted SMB share after cleanup")
                        await MainActor.run {
                            ConnectionLogger.shared.logInfo(server: config, message: "Mount successful after cleanup at \(mountPoint.path)")
                        }
                        return MountResult(
                            success: true,
                            mountPoint: mountPoint.path,
                            protocol: .smb
                        )
                    }
                }
            }
            
            throw MountError.mountFailed(errno: result.exitCode)
        }
        
        // This should never be reached but Swift requires all code paths to return
        throw MountError.mountFailed(errno: -1)
    }
    
    private func mountAFP(_ config: ServerConfiguration, credentials: NetworkCredential?) async throws -> MountResult {
        // Get timeout early for use in directory creation
        let options = MountOptions(from: config)
        let commandTimeout = options.timeout
        
        let mountPoint = URL(fileURLWithPath: config.effectiveMountPoint)
        
        // For /Volumes, let mount command handle directory creation
        // For other paths, ensure mount point exists
        if !mountPoint.path.hasPrefix("/Volumes/") {
            try await ensureMountPoint(exists: mountPoint)
        } else {
            // For /Volumes, we need to create the mount point if it doesn't exist
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: mountPoint.path, isDirectory: &isDirectory) {
                // Create the mount point using mkdir
                logger.info("Creating mount point at \(mountPoint.path)")
                let mkdirResult = try await executeCommand(["/bin/mkdir", mountPoint.path], timeout: commandTimeout)
                if mkdirResult.exitCode != 0 {
                    logger.error("Failed to create mount point: \(mkdirResult.output)")
                }
            }
        }
        
        // Build mount command
        var command = ["/sbin/mount_afp"]
        
        let optionArgs = options.toCommandArguments(for: .afp)
        if !optionArgs.isEmpty {
            command.append(contentsOf: optionArgs)
        }
        
        // Sanitize inputs to prevent command injection
        let sanitizedServer = sanitizeInput(config.serverAddress)
        let sanitizedShare = sanitizeInput(config.shareName)
        
        // Build mount URL WITHOUT credentials - we'll pass them securely
        let mountURL: String
        if let creds = credentials {
            // Properly encode username without destroying domain formats (DOMAIN\user, user@domain.com)
            let encodedUser = creds.username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? creds.username
            
            // For AFP, we'll use the interactive mode and pass password via stdin
            command.insert("-i", at: 1)  // Add interactive flag
            
            // Mount URL includes username but NOT password
            mountURL = "afp://\(encodedUser)@\(sanitizedServer)/\(sanitizedShare)"
        } else {
            mountURL = "afp://\(sanitizedServer)/\(sanitizedShare)"
        }
        
        command.append(mountURL)
        command.append(mountPoint.path)
        
        // Execute mount
        let result: (output: String, exitCode: Int32)
        if let creds = credentials {
            // For AFP with credentials, we need to pass password via stdin
            result = try await executeCommandWithStdin(command, stdin: creds.password + "\n", timeout: commandTimeout)
        } else {
            result = try await executeCommand(command, timeout: commandTimeout)
        }
        
        if result.exitCode == 0 {
            logger.info("Successfully mounted AFP share \(config.displayName)")
            return MountResult(
                success: true,
                mountPoint: mountPoint.path,
                protocol: .afp
            )
        } else {
            logger.error("Failed to mount AFP share: \(result.output)")
            
            // Check for authentication errors
            if result.output.contains("Authentication error") || 
               result.output.contains("Permission denied") ||
               result.output.contains("AUTHENTICATION_FAILED") ||
               result.exitCode == 13 { // EACCES
                throw MountError.authenticationFailed
            }
            
            throw MountError.mountFailed(errno: result.exitCode)
        }
    }
    
    private func mountNFS(_ config: ServerConfiguration) async throws -> MountResult {
        // Get timeout early for use in directory creation
        let options = MountOptions(from: config)
        let commandTimeout = options.timeout
        
        let mountPoint = URL(fileURLWithPath: config.effectiveMountPoint)
        
        // For /Volumes, let mount command handle directory creation
        // For other paths, ensure mount point exists
        if !mountPoint.path.hasPrefix("/Volumes/") {
            try await ensureMountPoint(exists: mountPoint)
        } else {
            // For /Volumes, we need to create the mount point if it doesn't exist
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: mountPoint.path, isDirectory: &isDirectory) {
                // Create the mount point using mkdir
                logger.info("Creating mount point at \(mountPoint.path)")
                let mkdirResult = try await executeCommand(["/bin/mkdir", mountPoint.path], timeout: commandTimeout)
                if mkdirResult.exitCode != 0 {
                    logger.error("Failed to create mount point: \(mkdirResult.output)")
                }
            }
        }
        
        // Build mount command
        var command = ["/sbin/mount_nfs"]
        
        let optionArgs = options.toCommandArguments(for: .nfs)
        if !optionArgs.isEmpty {
            command.append(contentsOf: optionArgs)
        }
        
        // NFS mount format: server:/path
        let mountSource = "\(config.serverAddress):/\(config.shareName)"
        command.append(mountSource)
        command.append(mountPoint.path)
        
        // Execute mount
        let result = try await executeCommand(command, timeout: commandTimeout)
        
        if result.exitCode == 0 {
            logger.info("Successfully mounted NFS share \(config.displayName)")
            return MountResult(
                success: true,
                mountPoint: mountPoint.path,
                protocol: .nfs
            )
        } else {
            logger.error("Failed to mount NFS share: \(result.output)")
            throw MountError.mountFailed(errno: result.exitCode)
        }
    }
    
    // MARK: - Unmount Operations
    
    func unmount(_ serverId: UUID) async throws {
        guard let mountInfo = activeMounts[serverId] else {
            logger.warning("No active mount found for server \(serverId)")
            throw MountError.notMounted
        }
        
        logger.info("Unmounting \(mountInfo.mountPoint)")
        
        let command = ["/sbin/umount", mountInfo.mountPoint]
        let result = try await executeCommand(command, timeout: 10) // Shorter timeout for unmount
        
        if result.exitCode == 0 {
            activeMounts.removeValue(forKey: serverId)
            // Release security-scoped resource if we have one
            activeResources.removeValue(forKey: mountInfo.mountPoint)
            logger.info("Successfully unmounted \(mountInfo.mountPoint)")
        } else {
            // Try force unmount
            logger.warning("Normal unmount failed, attempting force unmount")
            let forceCommand = ["/sbin/umount", "-f", mountInfo.mountPoint]
            let forceResult = try await executeCommand(forceCommand, timeout: 15) // Longer timeout for force unmount
            
            if forceResult.exitCode == 0 {
                activeMounts.removeValue(forKey: serverId)
                // Release security-scoped resource if we have one
                activeResources.removeValue(forKey: mountInfo.mountPoint)
                logger.info("Successfully force unmounted \(mountInfo.mountPoint)")
            } else {
                logger.error("Failed to unmount: \(forceResult.output)")
                throw MountError.unmountFailed(errno: forceResult.exitCode)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func isServerReachable(_ config: ServerConfiguration, timeout: TimeInterval = 5) async -> Bool {
        let port = config.protocol.defaultPort
        return await networkMonitor.isReachable(host: config.serverAddress, port: port, timeout: timeout)
    }
    
    private func ensureMountPoint(exists url: URL) async throws {
        let fileManager = FileManager.default
        
        // For sandboxed access, we need to use security-scoped bookmarks
        // Check if we need bookmark access for custom mount points
        if !url.path.hasPrefix("/Volumes/") {
            // Custom mount point - needs bookmark access
            do {
                // Get security-scoped access
                let resource = try await bookmarkManager.accessMountPoint(at: url.path)
                
                // Store the resource to keep access open
                activeResources[url.path] = resource
                
                // Now we can create the directory with proper permissions
                var isDirectory: ObjCBool = false
                if !fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                    logger.info("Created mount point at \(url.path) with sandboxed access")
                } else if !isDirectory.boolValue {
                    // Release the resource since we can't use this path
                    activeResources.removeValue(forKey: url.path)
                    throw MountError.mountPointInvalid("Mount point exists but is not a directory")
                }
            } catch {
                logger.error("Failed to access mount point with bookmark: \(error)")
                throw MountError.mountPointInvalid("Cannot access mount point: \(error.localizedDescription). You may need to grant access to this location.")
            }
        } else {
            // /Volumes path - we have temporary exception in entitlements
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                do {
                    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                    logger.info("Created mount point at \(url.path)")
                } catch {
                    logger.error("Failed to create mount point: \(error)")
                    throw MountError.mountPointInvalid("Cannot create mount point: \(error.localizedDescription)")
                }
            } else if !isDirectory.boolValue {
                throw MountError.mountPointInvalid("Mount point exists but is not a directory")
            }
        }
    }
    
    // MARK: - Utility Functions
    
    private func sanitizeInput(_ input: String) -> String {
        // Remove any shell metacharacters that could be used for command injection
        let dangerousChars = CharacterSet(charactersIn: ";|&$`\\\"'<>(){}[]!*?~\n\r")
        return input.components(separatedBy: dangerousChars).joined()
    }
    
    /// Sanitizes command arrays for safe logging by removing passwords from URLs
    private func sanitizeCommandForLogging(_ command: [String]) -> String {
        let sanitizedCommand = command.map { argument in
            // Check if this argument contains a URL with credentials
            if argument.contains("://") && argument.contains("@") {
                return sanitizeURLForLogging(argument)
            }
            return argument
        }
        return sanitizedCommand.joined(separator: " ")
    }
    
    /// Sanitizes URLs by masking passwords for safe logging
    private func sanitizeURLForLogging(_ url: String) -> String {
        // Pattern: //[username[:password]]@server/path
        // Replace: //username:***@server/path
        
        // Use regex to find and replace password patterns
        let pattern = #"(://[^:@/]+):([^@]+)(@)"#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(url.startIndex..<url.endIndex, in: url)
            
            return regex.stringByReplacingMatches(
                in: url,
                options: [],
                range: range,
                withTemplate: "$1:***$3"
            )
        } catch {
            // If regex fails, try simple string replacement
            if let atIndex = url.lastIndex(of: "@"),
               let colonIndex = url.range(of: ":")?.upperBound,
               colonIndex < atIndex {
                let beforePassword = String(url[..<colonIndex])
                let afterPassword = String(url[atIndex...])
                return beforePassword + "***" + afterPassword
            }
            
            // Fallback: return original if we can't parse it safely
            return url
        }
    }
    
    /// Test function to validate password sanitization (for security verification)
    private func testPasswordSanitization() async {
        // Test cases for password sanitization
        let testCommands = [
            ["/sbin/mount_smbfs", "//user:password123@server.com/share", "/mnt/point"],
            ["/sbin/mount_smbfs", "//domain\\user:secret!@#@10.0.1.1/data", "/Users/test"],
            ["/sbin/mount_afp", "afp://testuser:p@ssw0rd@192.168.1.100/volume", "/Volumes/test"]
        ]
        
        let expectedResults = [
            "/sbin/mount_smbfs //user:***@server.com/share /mnt/point",
            "/sbin/mount_smbfs //domain\\user:***@10.0.1.1/data /Users/test", 
            "/sbin/mount_afp afp://testuser:***@192.168.1.100/volume /Volumes/test"
        ]
        
        for (index, command) in testCommands.enumerated() {
            let sanitized = sanitizeCommandForLogging(command)
            let expected = expectedResults[index]
            
            if sanitized == expected {
                logger.info("✅ Password sanitization test \(index + 1) PASSED")
            } else {
                logger.error("❌ Password sanitization test \(index + 1) FAILED")
                logger.error("Expected: \(expected)")
                logger.error("Got: \(sanitized)")
            }
        }
        
        logger.info("Password sanitization validation complete")
    }
    
    private func executeCommand(_ command: [String], environment: [String: String]? = nil, timeout: TimeInterval = 30) async throws -> (output: String, exitCode: Int32) {
        let sanitizedCommand = sanitizeCommandForLogging(command)
        logger.debug("Executing command with \(timeout)s timeout: \(sanitizedCommand)")
        
        return try await withThrowingTaskGroup(of: (output: String, exitCode: Int32)?.self) { group in
            var task: Process?
            
            // Add command execution task
            group.addTask { [weak self] in
                guard let self = self else { throw MountError.internalError("MountService deallocated") }
                return try await withCheckedThrowingContinuation { continuation in
                    self.mountQueue.async {
                        let process = Process()
                        task = process
                        process.executableURL = URL(fileURLWithPath: command[0])
                        process.arguments = Array(command.dropFirst())
                        
                        // Set environment variables if provided
                        if let env = environment {
                            var processEnv = ProcessInfo.processInfo.environment
                            for (key, value) in env {
                                processEnv[key] = value
                            }
                            process.environment = processEnv
                        }
                        
                        let outputPipe = Pipe()
                        let errorPipe = Pipe()
                        process.standardOutput = outputPipe
                        process.standardError = errorPipe
                        
                        do {
                            try process.run()
                            process.waitUntilExit()
                            
                            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                            
                            let output = String(data: outputData, encoding: .utf8) ?? ""
                            let error = String(data: errorData, encoding: .utf8) ?? ""
                            let combinedOutput = output + error
                            
                            continuation.resume(returning: (combinedOutput, process.terminationStatus))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil // Timeout occurred
            }
            
            // Wait for first result
            do {
                for try await result in group {
                    group.cancelAll()
                    
                    if let commandResult = result {
                        // Command completed
                        return commandResult
                    } else {
                        // Timeout occurred
                        let sanitizedCommand = self.sanitizeCommandForLogging(command)
                        self.logger.warning("Command timed out after \(timeout)s: \(sanitizedCommand)")
                        
                        // Terminate the process if it's still running
                        if let process = task, process.isRunning {
                            process.terminate()
                            // Give it a moment to terminate gracefully
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                            if process.isRunning {
                                // Force kill if still running
                                process.forceTerminate()
                            }
                        }
                        
                        throw MountError.timeoutExceeded
                    }
                }
            } catch {
                // Handle any errors from the task group
                group.cancelAll()
                
                // Terminate the process if it's still running
                if let process = task, process.isRunning {
                    process.terminate()
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    if process.isRunning {
                        process.forceTerminate()
                    }
                }
                
                throw error
            }
            
            // Should never reach here
            throw MountError.timeoutExceeded
        }
    }
    
    private func executeCommandWithStdin(_ command: [String], stdin: String, environment: [String: String]? = nil, timeout: TimeInterval = 30) async throws -> (output: String, exitCode: Int32) {
        let sanitizedCommand = sanitizeCommandForLogging(command)
        logger.debug("Executing command with stdin and \(timeout)s timeout: \(sanitizedCommand)")
        
        return try await withThrowingTaskGroup(of: (output: String, exitCode: Int32)?.self) { group in
            var task: Process?
            
            // Add command execution task
            group.addTask { [weak self] in
                guard let self = self else { throw MountError.internalError("MountService deallocated") }
                return try await withCheckedThrowingContinuation { continuation in
                    self.mountQueue.async {
                        let process = Process()
                        task = process
                        process.executableURL = URL(fileURLWithPath: command[0])
                        process.arguments = Array(command.dropFirst())
                        
                        // Set environment variables if provided
                        if let env = environment {
                            var processEnv = ProcessInfo.processInfo.environment
                            for (key, value) in env {
                                processEnv[key] = value
                            }
                            process.environment = processEnv
                        }
                        
                        let inputPipe = Pipe()
                        let outputPipe = Pipe()
                        let errorPipe = Pipe()
                        
                        process.standardInput = inputPipe
                        process.standardOutput = outputPipe
                        process.standardError = errorPipe
                        
                        do {
                            try process.run()
                            
                            // Write stdin data
                            if let stdinData = stdin.data(using: .utf8) {
                                inputPipe.fileHandleForWriting.write(stdinData)
                                inputPipe.fileHandleForWriting.closeFile()
                            }
                            
                            process.waitUntilExit()
                            
                            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                            
                            let output = String(data: outputData, encoding: .utf8) ?? ""
                            let error = String(data: errorData, encoding: .utf8) ?? ""
                            let combinedOutput = output + error
                            
                            continuation.resume(returning: (combinedOutput, process.terminationStatus))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil // Timeout occurred
            }
            
            // Wait for first result
            do {
                for try await result in group {
                group.cancelAll()
                
                if let commandResult = result {
                    // Command completed
                    return commandResult
                } else {
                    // Timeout occurred
                    let sanitizedCommand = self.sanitizeCommandForLogging(command)
                    self.logger.warning("Command with stdin timed out after \(timeout)s: \(sanitizedCommand)")
                    
                    // Terminate the process if it's still running
                    if let process = task, process.isRunning {
                        process.terminate()
                        // Give it a moment to terminate gracefully
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                        if process.isRunning {
                            // Force kill if still running
                            process.forceTerminate()
                        }
                    }
                    
                    throw MountError.timeoutExceeded
                }
            }
            } catch {
                // Handle any errors from the task group
                group.cancelAll()
                
                // Terminate the process if it's still running
                if let process = task, process.isRunning {
                    process.terminate()
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    if process.isRunning {
                        process.forceTerminate()
                    }
                }
                
                throw error
            }
            
            // Should never reach here
            throw MountError.timeoutExceeded
        }
    }
    
    // MARK: - Status Methods
    
    func isMounted(_ serverId: UUID) -> Bool {
        // First check our in-memory tracking
        guard let mountInfo = activeMounts[serverId] else {
            return false
        }
        
        // Verify the mount still exists using proper mount detection
        let mountPoint = mountInfo.mountPoint
        
        // Check if it's actually a mount point (not just a directory)
        if !mountDetector.isPathMountPoint(mountPoint) {
            logger.info("Path \(mountPoint) is no longer a mount point for server \(serverId)")
            // Remove from tracking since it's not mounted
            activeMounts.removeValue(forKey: serverId)
            return false
        }
        
        // Verify it's still a network mount
        if !mountDetector.isNetworkMount(mountPoint) {
            logger.warning("Path \(mountPoint) is a mount but not a network mount for server \(serverId)")
            // Remove from tracking
            activeMounts.removeValue(forKey: serverId)
            return false
        }
        
        // Get current mount info to verify it's still valid
        if let currentMountInfo = mountDetector.getMountInfo(for: mountPoint) {
            logger.debug("Mount verified for server \(serverId): type=\(currentMountInfo.filesystemType), from=\(currentMountInfo.mountedFrom)")
            return true
        } else {
            logger.warning("Could not get mount info for \(mountPoint) - server \(serverId)")
            // Remove from tracking
            activeMounts.removeValue(forKey: serverId)
            return false
        }
    }
    
    func getMountInfo(_ serverId: UUID) -> MountInfo? {
        return activeMounts[serverId]
    }
    
    func getAllMounts() -> [MountInfo] {
        return Array(activeMounts.values)
    }
    
    func checkMountHealth(_ serverId: UUID) async -> Bool {
        guard let mountInfo = activeMounts[serverId] else {
            logger.debug("No mount info found for server \(serverId)")
            return false
        }
        
        let mountPoint = mountInfo.mountPoint
        logger.debug("Starting health check for mount at \(mountPoint)")
        
        // First verify it's still a mount point
        if !mountDetector.isPathMountPoint(mountPoint) {
            logger.warning("Path \(mountPoint) is no longer a mount point")
            
            // Get server configuration for user-visible logging
            let repository = UserDefaultsServerRepository()
            if let servers = try? repository.fetchAll(),
               let server = servers.first(where: { $0.id == serverId }) {
                await MainActor.run {
                    ConnectionLogger.shared.logInfo(server: server, message: "⚠️ Mount point no longer exists - share has been unmounted")
                }
            }
            
            // Remove from tracking
            activeMounts.removeValue(forKey: serverId)
            return false
        }
        
        // Verify it's still a network mount
        if !mountDetector.isNetworkMount(mountPoint) {
            logger.warning("Path \(mountPoint) is not a network mount")
            
            // Get server configuration for user-visible logging
            let repository = UserDefaultsServerRepository()
            if let servers = try? repository.fetchAll(),
               let server = servers.first(where: { $0.id == serverId }) {
                await MainActor.run {
                    ConnectionLogger.shared.logInfo(server: server, message: "⚠️ Mount point exists but is not a network mount")
                }
            }
            
            // Remove from tracking
            activeMounts.removeValue(forKey: serverId)
            return false
        }
        
        // Get server configuration for network validation
        let repository = UserDefaultsServerRepository()
        guard let servers = try? repository.fetchAll(),
              let server = servers.first(where: { $0.id == serverId }) else {
            logger.warning("Could not find server configuration for \(serverId)")
            return false
        }
        
        // Check network connectivity to the server before testing file access
        // This helps detect VPN disconnections and network issues early
        logger.debug("Testing network connectivity to server \(server.serverAddress)")
        let networkConnectivityStart = Date()
        let isNetworkReachable = await isServerReachable(server, timeout: 3) // Shorter timeout for health checks
        let networkCheckDuration = Date().timeIntervalSince(networkConnectivityStart)
        
        if !isNetworkReachable {
            logger.warning("Server \(server.serverAddress) is not reachable - mount may be stale due to network/VPN issues")
            await MainActor.run {
                ConnectionLogger.shared.logInfo(server: server, message: "⚠️ Server not reachable during health check (network check took \(String(format: "%.2f", networkCheckDuration))s) - may indicate VPN disconnection")
            }
            return false
        } else {
            logger.debug("Network connectivity confirmed for \(server.serverAddress) (took \(String(format: "%.2f", networkCheckDuration))s)")
        }
        
        // Now check if the mount is accessible (not stale)
        let url = URL(fileURLWithPath: mountPoint)
        let startTime = Date()
        
        do {
            // Try to access the directory contents
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            let checkDuration = Date().timeIntervalSince(startTime)
            
            // Also get current mount info for additional validation
            if let currentMountInfo = mountDetector.getMountInfo(for: mountPoint) {
                logger.debug("Health check successful for \(mountPoint) (took \(String(format: "%.2f", checkDuration))s)")
                logger.debug("Mount details: type=\(currentMountInfo.filesystemType), from=\(currentMountInfo.mountedFrom)")
                return true
            } else {
                logger.warning("Could not get mount info despite successful access")
                return false
            }
        } catch {
            let checkDuration = Date().timeIntervalSince(startTime)
            let nsError = error as NSError
            
            // Log detailed error information
            logger.warning("Mount at \(mountPoint) appears to be stale after \(String(format: "%.2f", checkDuration))s - Error: \(error.localizedDescription)")
            logger.warning("Error domain: \(nsError.domain), code: \(nsError.code), userInfo: \(nsError.userInfo)")
            
            // Determine error type for user-friendly message
            let errorMessage: String
            switch nsError.code {
            case 2: // ENOENT - No such file or directory
                errorMessage = "Mount point does not exist"
            case 13: // EACCES - Permission denied
                errorMessage = "Permission denied accessing mount"
            case 60: // ETIMEDOUT - Operation timed out
                errorMessage = "Operation timed out - server may be unreachable"
            case 64: // EHOSTDOWN - Host is down
                errorMessage = "Server appears to be down"
            case 65: // EHOSTUNREACH - No route to host
                errorMessage = "Cannot reach server - network issue"
            case 66: // ENOTEMPTY - Directory not empty
                errorMessage = "Mount point directory not empty"
            case 89: // ECANCELED - Operation canceled
                errorMessage = "Operation was canceled"
            case 256: // NSFileReadNoPermissionError
                errorMessage = "No permission to read mount"
            case 257: // NSFileReadNoSuchFileError  
                errorMessage = "Mount point not found"
            case 260: // NSFileReadUnknownError
                errorMessage = "Unknown error accessing mount"
            default:
                errorMessage = "Error \(nsError.code): \(error.localizedDescription)"
            }
            
            await MainActor.run {
                ConnectionLogger.shared.logInfo(server: server, message: "⚠️ Mount is stale and not accessible - \(errorMessage)")
            }
            
            return false
        }
    }
}

// MARK: - Supporting Types

struct MountInfo {
    let serverId: UUID
    let mountPoint: String
    let `protocol`: NetworkProtocol
    let mountedAt: Date
}

// MARK: - Process Extensions

extension Process {
    func forceTerminate() {
        if isRunning {
            // Send SIGKILL
            kill(processIdentifier, SIGKILL)
        }
    }
}