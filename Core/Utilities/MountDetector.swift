//
//  MountDetector.swift
//  MacMount
//
//  Provides reliable mount point detection using native macOS APIs
//

import Foundation
import OSLog

/// Utility class for detecting mount points and their properties
class MountDetector {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "MountDetector")
    
    // Cache for mount detection results
    private var mountPointCache: [String: (isMountPoint: Bool, timestamp: Date)] = [:] 
    private var networkMountCache: [String: (isNetworkMount: Bool, timestamp: Date)] = [:]
    private var mountInfoCache: [String: (info: MountInfo?, timestamp: Date)] = [:]
    private let cacheExpiration: TimeInterval = 5.0 // 5 seconds cache
    private let cacheLock = NSLock()
    
    /// Network filesystem type names
    private let networkFilesystemTypes = Set([
        "smbfs",     // SMB/CIFS
        "afpfs",     // AFP
        "nfs",       // NFS
        "webdav",    // WebDAV
        "cifs",      // Alternative CIFS name
        "smb",       // Alternative SMB name
        "ftp",       // FTP
        "afp"        // Alternative AFP name
    ])
    
    /// Check if a path is currently a mount point
    /// - Parameter path: The path to check
    /// - Returns: true if the path is a mount point, false otherwise
    func isPathMountPoint(_ path: String) -> Bool {
        // First, normalize the path
        let normalizedPath = NSString(string: path).standardizingPath
        
        // Check cache first
        cacheLock.lock()
        if let cached = mountPointCache[normalizedPath],
           Date().timeIntervalSince(cached.timestamp) < cacheExpiration {
            let result = cached.isMountPoint
            cacheLock.unlock()
            logger.debug("Cache hit for mount point check: \(normalizedPath) = \(result)")
            return result
        }
        cacheLock.unlock()
        
        // Get stat info for the path and its parent
        var pathStat = stat()
        var parentStat = stat()
        
        // Get path stats
        guard stat(normalizedPath, &pathStat) == 0 else {
            logger.debug("Failed to stat path: \(normalizedPath)")
            return false
        }
        
        // Get parent directory stats
        let parentPath = NSString(string: normalizedPath).deletingLastPathComponent
        guard stat(parentPath, &parentStat) == 0 else {
            logger.debug("Failed to stat parent path: \(parentPath)")
            return false
        }
        
        // A path is a mount point if:
        // 1. It's on a different device than its parent, OR
        // 2. It's the same inode as its parent (for root filesystem)
        let isDifferentDevice = pathStat.st_dev != parentStat.st_dev
        let isSameInode = pathStat.st_ino == parentStat.st_ino && normalizedPath != "/"
        
        if isDifferentDevice || isSameInode {
            logger.debug("Path \(normalizedPath) is a mount point (different device: \(isDifferentDevice), same inode: \(isSameInode))")
            
            // Cache the positive result
            cacheLock.lock()
            mountPointCache[normalizedPath] = (true, Date())
            cacheLock.unlock()
            
            return true
        }
        
        // Additionally, use statfs to check if this exact path is a mount point
        var statfsBuf = statfs()
        if statfs(normalizedPath, &statfsBuf) == 0 {
            let mountedPath = withUnsafePointer(to: &statfsBuf.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                    String(cString: $0)
                }
            }
            let isMountPoint = mountedPath == normalizedPath
            
            if isMountPoint {
                logger.debug("Path \(normalizedPath) confirmed as mount point via statfs")
            }
            
            // Cache the result
            cacheLock.lock()
            mountPointCache[normalizedPath] = (isMountPoint, Date())
            cacheLock.unlock()
            
            return isMountPoint
        }
        
        // Cache the negative result
        cacheLock.lock()
        mountPointCache[normalizedPath] = (false, Date())
        cacheLock.unlock()
        
        return false
    }
    
    /// Check if a mount point is a network mount
    /// - Parameter path: The mount point path to check
    /// - Returns: true if it's a network mount, false if local or not a mount
    func isNetworkMount(_ path: String) -> Bool {
        let normalizedPath = NSString(string: path).standardizingPath
        
        // Check cache first
        cacheLock.lock()
        if let cached = networkMountCache[normalizedPath],
           Date().timeIntervalSince(cached.timestamp) < cacheExpiration {
            let result = cached.isNetworkMount
            cacheLock.unlock()
            logger.debug("Cache hit for network mount check: \(normalizedPath) = \(result)")
            return result
        }
        cacheLock.unlock()
        
        var statfsBuf = statfs()
        guard statfs(normalizedPath, &statfsBuf) == 0 else {
            logger.debug("Failed to statfs path: \(normalizedPath)")
            return false
        }
        
        // Check if it's actually the mount point for this filesystem
        let mountedPath = withUnsafePointer(to: &statfsBuf.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }
        guard mountedPath == normalizedPath else {
            logger.debug("Path \(normalizedPath) is not a mount point (mounted at: \(mountedPath))")
            return false
        }
        
        // Get filesystem type
        let filesystemType = withUnsafePointer(to: &statfsBuf.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }.lowercased()
        logger.debug("Filesystem type for \(normalizedPath): \(filesystemType)")
        
        // Check if it's a network filesystem type
        let isNetwork = networkFilesystemTypes.contains(filesystemType)
        
        // Additional check: network mounts typically don't have MNT_LOCAL flag
        let isLocal = (statfsBuf.f_flags & UInt32(MNT_LOCAL)) != 0
        
        logger.debug("Mount \(normalizedPath): filesystem=\(filesystemType), isNetwork=\(isNetwork), hasLocalFlag=\(isLocal)")
        
        let result = isNetwork || !isLocal
        
        // Cache the result
        cacheLock.lock()
        networkMountCache[normalizedPath] = (result, Date())
        cacheLock.unlock()
        
        return result
    }
    
    /// Get detailed mount information for a path
    /// - Parameter path: The path to check
    /// - Returns: Mount information if the path is a mount point, nil otherwise
    func getMountInfo(for path: String) -> MountPointInfo? {
        let normalizedPath = NSString(string: path).standardizingPath
        
        var statfsBuf = statfs()
        guard statfs(normalizedPath, &statfsBuf) == 0 else {
            return nil
        }
        
        let mountedPath = withUnsafePointer(to: &statfsBuf.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }
        guard mountedPath == normalizedPath else {
            // Not a mount point
            return nil
        }
        
        let filesystemType = withUnsafePointer(to: &statfsBuf.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }
        let mountedFrom = withUnsafePointer(to: &statfsBuf.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }
        let isLocal = (statfsBuf.f_flags & UInt32(MNT_LOCAL)) != 0
        let isReadOnly = (statfsBuf.f_flags & UInt32(MNT_RDONLY)) != 0
        
        return MountPointInfo(
            mountPoint: mountedPath,
            mountedFrom: mountedFrom,
            filesystemType: filesystemType,
            isLocal: isLocal,
            isReadOnly: isReadOnly,
            totalSpace: statfsBuf.f_blocks * UInt64(statfsBuf.f_bsize),
            freeSpace: statfsBuf.f_bfree * UInt64(statfsBuf.f_bsize)
        )
    }
    
    /// Get all currently mounted filesystems
    /// - Returns: Array of mount information for all mounted filesystems
    func getAllMounts() -> [MountPointInfo] {
        var mounts: [MountPointInfo] = []
        
        // Get the number of mounted filesystems
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else {
            logger.error("getfsstat failed to get mount count")
            return mounts
        }
        
        // Allocate buffer for mount information
        var statfsBufs = Array<statfs>(repeating: statfs(), count: Int(count))
        
        // Get mount information
        let actualCount = getfsstat(&statfsBufs, Int32(Int(count) * MemoryLayout<statfs>.size), MNT_NOWAIT)
        guard actualCount > 0 else {
            logger.error("getfsstat failed to get mount information")
            return mounts
        }
        
        // Process each mount
        for i in 0..<Int(actualCount) {
            let statfsBuf = statfsBufs[i]
            
            let mountPoint = withUnsafePointer(to: statfsBuf.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                    String(cString: $0)
                }
            }
            let mountedFrom = withUnsafePointer(to: statfsBuf.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                    String(cString: $0)
                }
            }
            let filesystemType = withUnsafePointer(to: statfsBuf.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                    String(cString: $0)
                }
            }
            let isLocal = (statfsBuf.f_flags & UInt32(MNT_LOCAL)) != 0
            let isReadOnly = (statfsBuf.f_flags & UInt32(MNT_RDONLY)) != 0
            
            let mountInfo = MountPointInfo(
                mountPoint: mountPoint,
                mountedFrom: mountedFrom,
                filesystemType: filesystemType,
                isLocal: isLocal,
                isReadOnly: isReadOnly,
                totalSpace: statfsBuf.f_blocks * UInt64(statfsBuf.f_bsize),
                freeSpace: statfsBuf.f_bfree * UInt64(statfsBuf.f_bsize)
            )
            
            mounts.append(mountInfo)
        }
        
        return mounts
    }
    
    /// Get all network mounts
    /// - Returns: Array of mount information for network filesystems only
    func getNetworkMounts() -> [MountPointInfo] {
        return getAllMounts().filter { mountInfo in
            let isNetworkType = networkFilesystemTypes.contains(mountInfo.filesystemType.lowercased())
            return isNetworkType || !mountInfo.isLocal
        }
    }
    
    /// Check if a specific server share is mounted
    /// - Parameters:
    ///   - serverAddress: The server address (hostname or IP)
    ///   - shareName: The share name
    /// - Returns: Mount information if found, nil otherwise
    func findMount(server serverAddress: String, share shareName: String) -> MountPointInfo? {
        let networkMounts = getNetworkMounts()
        
        for mount in networkMounts {
            // Parse the mounted from string to check if it matches
            // Format examples:
            // SMB: //username@server/share or //server/share
            // AFP: afp://username@server/share or afp://server/share  
            // NFS: server:/share
            
            let mountedFrom = mount.mountedFrom.lowercased()
            let serverLower = serverAddress.lowercased()
            let shareLower = shareName.lowercased()
            
            // Check different mount formats
            if mountedFrom.contains(serverLower) && mountedFrom.contains(shareLower) {
                logger.debug("Found mount for \(serverAddress)/\(shareName) at \(mount.mountPoint)")
                return mount
            }
        }
        
        return nil
    }
    
    /// Clear all caches
    func clearCache() {
        cacheLock.lock()
        mountPointCache.removeAll()
        networkMountCache.removeAll()
        mountInfoCache.removeAll()
        cacheLock.unlock()
        logger.debug("Mount detection caches cleared")
    }
    
    /// Clean up expired cache entries
    private func cleanupCache() {
        let now = Date()
        let expiredTime = cacheExpiration * 2 // Keep entries for 2x expiration time
        
        mountPointCache = mountPointCache.filter { _, value in
            now.timeIntervalSince(value.timestamp) < expiredTime
        }
        
        networkMountCache = networkMountCache.filter { _, value in
            now.timeIntervalSince(value.timestamp) < expiredTime
        }
        
        mountInfoCache = mountInfoCache.filter { _, value in
            now.timeIntervalSince(value.timestamp) < expiredTime
        }
    }
}

/// Information about a mount point
struct MountPointInfo {
    let mountPoint: String
    let mountedFrom: String
    let filesystemType: String
    let isLocal: Bool
    let isReadOnly: Bool
    let totalSpace: UInt64
    let freeSpace: UInt64
    
    var isNetworkMount: Bool {
        let networkTypes = Set(["smbfs", "afpfs", "nfs", "webdav", "cifs", "smb", "ftp", "afp"])
        return networkTypes.contains(filesystemType.lowercased()) || !isLocal
    }
}