//
//  BookmarkManager.swift
//  MacMount
//
//  Security-scoped bookmark management for sandboxed mount point access
//

import Foundation
import os.log
import Combine

/// Thread-safe wrapper for UserDefaults operations
/// Prevents race conditions during concurrent bookmark storage access
private final class ThreadSafeUserDefaults {
    private let userDefaults: UserDefaults
    private let lock = NSLock()
    
    init(_ userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    /// Thread-safe data retrieval
    func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return userDefaults.data(forKey: key)
    }
    
    /// Thread-safe data storage with atomic write operation
    func set(_ data: Data?, forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        // Perform atomic write operation
        if let data = data {
            userDefaults.set(data, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
        
        // Ensure data is persisted immediately
        return userDefaults.synchronize()
    }
    
    /// Thread-safe removal
    func removeObject(forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        userDefaults.removeObject(forKey: key)
        return userDefaults.synchronize()
    }
}

/// Manages security-scoped bookmarks for mount points in a sandboxed environment
/// 
/// This service handles:
/// - Creating and storing security-scoped bookmarks for mount point directories
/// - Resolving bookmarks to access mount points with proper permissions
/// - Managing bookmark lifecycle and renewal
/// - Migration from non-sandboxed to sandboxed storage
actor BookmarkManager {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.example.macmount", category: "BookmarkManager")
    private let bookmarkKey = "com.example.macmount.mountPointBookmarks"
    private let threadSafeDefaults = ThreadSafeUserDefaults()
    
    /// Current bookmark storage mapped by mount point path
    private var bookmarks: [String: Data] = [:]
    
    /// Tracks which mount points have been successfully accessed this session
    private var accessedMountPoints: Set<String> = []
    
    // MARK: - Initialization
    
    init() {
        Task {
            await loadBookmarks()
        }
    }
    
    // MARK: - Public Methods
    
    /// Creates a security-scoped bookmark for a mount point directory
    /// - Parameter url: The URL of the mount point directory
    /// - Returns: The bookmark data if successful
    /// - Throws: BookmarkError if creation fails
    func createBookmark(for url: URL) async throws -> Data {
        // Create parent directory if needed
        let parentDir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        
        // Create the mount point directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        logger.info("Creating security-scoped bookmark for: \(url.path)")
        
        // Ensure the URL is a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw BookmarkError.notADirectory(url)
        }
        
        do {
            // Create bookmark with read/write access for mount operations
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            // Store the bookmark
            bookmarks[url.path] = bookmarkData
            await saveBookmarks()
            
            logger.info("Successfully created bookmark for: \(url.path)")
            return bookmarkData
        } catch {
            logger.error("Failed to create bookmark for \(url.path): \(error.localizedDescription)")
            throw BookmarkError.creationFailed(url, error)
        }
    }
    
    /// Resolves a bookmark and provides access to the mount point
    /// - Parameter path: The mount point path
    /// - Returns: A scope guard that must be retained while accessing the resource
    /// - Throws: BookmarkError if resolution fails
    func accessMountPoint(at path: String) async throws -> SecurityScopedResource {
        logger.debug("Requesting access to mount point: \(path)")
        
        guard let bookmarkData = bookmarks[path] else {
            logger.error("No bookmark found for path: \(path)")
            throw BookmarkError.bookmarkNotFound(path)
        }
        
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            // Handle stale bookmarks
            if isStale {
                logger.warning("Bookmark is stale for: \(path), attempting renewal")
                let newBookmark = try await createBookmark(for: url)
                bookmarks[path] = newBookmark
                await saveBookmarks()
            }
            
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                throw BookmarkError.accessDenied(url)
            }
            
            accessedMountPoints.insert(path)
            logger.debug("Successfully accessed mount point: \(path)")
            
            return SecurityScopedResource(url: url) { [weak self] in
                url.stopAccessingSecurityScopedResource()
                self?.logger.debug("Released access to mount point: \(path)")
            }
        } catch {
            logger.error("Failed to resolve bookmark for \(path): \(error.localizedDescription)")
            
            // If bookmark is corrupted, remove it and suggest recreation
            if error.localizedDescription.contains("isn't in the correct format") ||
               error.localizedDescription.contains("corrupt") {
                logger.warning("Bookmark appears corrupted, removing it")
                bookmarks.removeValue(forKey: path)
                await saveBookmarks()
            }
            
            throw BookmarkError.resolutionFailed(path, error)
        }
    }
    
    /// Removes a bookmark for a mount point
    /// - Parameter path: The mount point path to remove
    func removeBookmark(for path: String) async {
        logger.info("Removing bookmark for: \(path)")
        bookmarks.removeValue(forKey: path)
        accessedMountPoints.remove(path)
        await saveBookmarks()
    }
    
    /// Checks if a bookmark exists for a mount point
    /// - Parameter path: The mount point path
    /// - Returns: true if a bookmark exists
    func hasBookmark(for path: String) async -> Bool {
        return bookmarks[path] != nil
    }
    
    /// Validates all stored bookmarks and removes stale ones
    func validateBookmarks() async {
        logger.info("Validating all stored bookmarks")
        var staleBookmarks: [String] = []
        
        for (path, bookmarkData) in bookmarks {
            var isStale = false
            do {
                _ = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if isStale {
                    staleBookmarks.append(path)
                }
            } catch {
                logger.warning("Invalid bookmark for \(path): \(error.localizedDescription)")
                staleBookmarks.append(path)
            }
        }
        
        // Remove stale bookmarks
        for path in staleBookmarks {
            await removeBookmark(for: path)
        }
        
        logger.info("Bookmark validation complete. Removed \(staleBookmarks.count) stale bookmarks")
    }
    
    // MARK: - Migration Support
    
    /// Migrates mount points from non-sandboxed to sandboxed environment
    /// - Parameter mountPoints: Array of mount point paths to migrate
    /// - Returns: Migration results for each mount point
    func migrateMountPoints(_ mountPoints: [String]) async -> [MigrationResult] {
        logger.info("Starting mount point migration for \(mountPoints.count) paths")
        
        var results: [MigrationResult] = []
        
        for path in mountPoints {
            let url = URL(fileURLWithPath: path)
            
            // Check if directory exists
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                results.append(MigrationResult(path: path, success: false, 
                              error: "Directory does not exist"))
                continue
            }
            
            // Try to create bookmark
            do {
                _ = try await createBookmark(for: url)
                results.append(MigrationResult(path: path, success: true, error: nil))
            } catch {
                results.append(MigrationResult(path: path, success: false, 
                              error: error.localizedDescription))
            }
        }
        
        logger.info("Migration complete. Success: \(results.filter { $0.success }.count)/\(results.count)")
        return results
    }
    
    // MARK: - Private Methods
    
    private func loadBookmarks() async {
        // Retry logic for loading bookmarks with exponential backoff
        for attempt in 1...3 {
            guard let data = threadSafeDefaults.data(forKey: bookmarkKey) else {
                logger.info("No existing bookmarks found")
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode([String: Data].self, from: data)
                bookmarks = decoded
                logger.info("Loaded \(self.bookmarks.count) bookmarks")
                return
            } catch {
                logger.warning("Failed to decode bookmarks on attempt \(attempt): \(error.localizedDescription)")
                
                if attempt < 3 {
                    // Exponential backoff: 100ms, 200ms, 400ms
                    let delay = Double(100 * (1 << (attempt - 1))) / 1000.0
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    // If all attempts fail, clear corrupted data and start fresh
                    logger.error("All bookmark loading attempts failed, clearing corrupted data")
                    _ = threadSafeDefaults.removeObject(forKey: bookmarkKey)
                    bookmarks = [:]
                }
            }
        }
    }
    
    private func saveBookmarks() async {
        // Validate bookmark data before saving
        guard validateBookmarkData() else {
            logger.error("Bookmark data validation failed, skipping save operation")
            return
        }
        
        // Retry logic for saving bookmarks with exponential backoff
        for attempt in 1...3 {
            do {
                let encoded = try JSONEncoder().encode(bookmarks)
                
                // Additional validation: ensure encoded data is reasonable size (not corrupted)
                guard encoded.count > 0 && encoded.count < 10_000_000 else { // 10MB limit
                    throw BookmarkError.saveFailed("Encoded bookmark data size is invalid: \(encoded.count) bytes")
                }
                
                // Attempt atomic write with thread-safe UserDefaults
                let success = threadSafeDefaults.set(encoded, forKey: bookmarkKey)
                
                if success {
                    logger.debug("Saved \(self.bookmarks.count) bookmarks (\(encoded.count) bytes)")
                    return
                } else {
                    throw BookmarkError.saveFailed("UserDefaults synchronization failed")
                }
            } catch {
                logger.warning("Failed to save bookmarks on attempt \(attempt): \(error.localizedDescription)")
                
                if attempt < 3 {
                    // Exponential backoff: 100ms, 200ms, 400ms
                    let delay = Double(100 * (1 << (attempt - 1))) / 1000.0
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    logger.error("All bookmark saving attempts failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Validates bookmark data integrity before save operations
    private func validateBookmarkData() -> Bool {
        // Check that all bookmarks have valid paths and data
        for (path, data) in bookmarks {
            // Validate path
            guard !path.isEmpty, path.hasPrefix("/"), data.count > 0 else {
                logger.warning("Invalid bookmark detected - path: '\(path)', data size: \(data.count)")
                return false
            }
            
            // Basic bookmark data validation (should start with known bookmark plist header)
            let bookmarkPlistHeader = Data([0x62, 0x6F, 0x6F, 0x6B]) // "book" in hex
            guard data.count >= 4, data.prefix(4) == bookmarkPlistHeader else {
                logger.warning("Bookmark data appears corrupted for path: \(path)")
                return false
            }
        }
        
        logger.debug("Bookmark data validation passed for \(self.bookmarks.count) bookmarks")
        return true
    }
}

// MARK: - Supporting Types

/// Represents a security-scoped resource that automatically releases access when deallocated
final class SecurityScopedResource {
    let url: URL
    private let cleanup: () -> Void
    
    init(url: URL, cleanup: @escaping () -> Void) {
        self.url = url
        self.cleanup = cleanup
    }
    
    deinit {
        cleanup()
    }
}

/// Migration result for a single mount point
struct MigrationResult {
    let path: String
    let success: Bool
    let error: String?
}

/// Errors specific to bookmark operations
enum BookmarkError: LocalizedError {
    case notADirectory(URL)
    case creationFailed(URL, Error)
    case bookmarkNotFound(String)
    case resolutionFailed(String, Error)
    case accessDenied(URL)
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notADirectory(let url):
            return "The specified path is not a directory: \(url.path)"
        case .creationFailed(let url, let error):
            return "Failed to create bookmark for \(url.path): \(error.localizedDescription)"
        case .bookmarkNotFound(let path):
            return "No bookmark found for path: \(path)"
        case .resolutionFailed(let path, let error):
            return "Failed to resolve bookmark for \(path): \(error.localizedDescription)"
        case .accessDenied(let url):
            return "Access denied to security-scoped resource: \(url.path)"
        case .saveFailed(let reason):
            return "Failed to save bookmarks: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notADirectory:
            return "Ensure the mount point directory exists before creating a bookmark"
        case .creationFailed:
            return "Check that the app has permission to access this location"
        case .bookmarkNotFound:
            return "Re-select the mount point directory to create a new bookmark"
        case .resolutionFailed(_, let error):
            if error.localizedDescription.contains("isn't in the correct format") ||
               error.localizedDescription.contains("corrupt") {
                return "The bookmark was corrupted and has been removed. Please re-select the mount point directory"
            } else {
                return "The bookmark may be invalid. Try re-selecting the directory"
            }
        case .accessDenied:
            return "The app may not have permission to access this location"
        case .saveFailed:
            return "The bookmark storage may be temporarily unavailable. The operation will be retried automatically"
        }
    }
}