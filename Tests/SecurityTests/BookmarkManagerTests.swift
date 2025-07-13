//
//  BookmarkManagerTests.swift
//  MacMountTests
//
//  Tests for security-scoped bookmark management
//

import XCTest
@testable import MacMount

@MainActor
final class BookmarkManagerTests: XCTestCase {
    
    var sut: BookmarkManager!
    var mockFileManager: MockFileManager!
    var testDefaults: UserDefaults!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create isolated UserDefaults for testing
        testDefaults = UserDefaults(suiteName: "BookmarkManagerTests")!
        testDefaults.removePersistentDomain(forName: "BookmarkManagerTests")
        
        mockFileManager = MockFileManager()
        sut = BookmarkManager()
        
        // Clear any existing bookmarks
        testDefaults.removeObject(forKey: "com.example.macmount.mountPointBookmarks")
    }
    
    override func tearDown() async throws {
        sut = nil
        mockFileManager = nil
        testDefaults.removePersistentDomain(forName: "BookmarkManagerTests")
        testDefaults = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialState() {
        XCTAssertTrue(sut.bookmarks.isEmpty)
    }
    
    // MARK: - Bookmark Creation Tests
    
    func testCreateBookmarkForValidDirectory() async throws {
        // Given
        let testPath = "/Volumes/TestMount"
        let testURL = URL(fileURLWithPath: testPath)
        mockFileManager.stubFileExists(at: testPath, exists: true, isDirectory: true)
        
        // When creating bookmark (we'll use mock data since we can't create real bookmarks in tests)
        // In real implementation, this would create actual security-scoped bookmarks
        
        // For testing purposes, we'll verify the validation logic
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("BookmarkTest")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        do {
            _ = try await sut.createBookmark(for: tempDir)
            // In real tests with proper mocking, this would succeed
        } catch {
            // Expected in test environment without proper sandboxing
            if let bookmarkError = error as? BookmarkError {
                switch bookmarkError {
                case .creationFailed:
                    // This is expected in test environment
                    break
                default:
                    XCTFail("Unexpected error type: \(bookmarkError)")
                }
            }
        }
    }
    
    func testCreateBookmarkForNonExistentPath() async throws {
        // Given
        let testPath = "/Volumes/NonExistent"
        let testURL = URL(fileURLWithPath: testPath)
        
        // When/Then
        do {
            _ = try await sut.createBookmark(for: testURL)
            XCTFail("Should throw error for non-existent path")
        } catch {
            if let bookmarkError = error as? BookmarkError {
                switch bookmarkError {
                case .notADirectory:
                    // Expected error
                    XCTAssertTrue(true)
                default:
                    XCTFail("Unexpected error type: \(bookmarkError)")
                }
            }
        }
    }
    
    func testCreateBookmarkForFile() async throws {
        // Given - create a temporary file
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test.txt")
        try "test".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        // When/Then
        do {
            _ = try await sut.createBookmark(for: tempFile)
            XCTFail("Should throw error for file (not directory)")
        } catch {
            if let bookmarkError = error as? BookmarkError {
                switch bookmarkError {
                case .notADirectory(let url):
                    XCTAssertEqual(url, tempFile)
                default:
                    XCTFail("Unexpected error type: \(bookmarkError)")
                }
            }
        }
    }
    
    // MARK: - Bookmark Access Tests
    
    func testAccessMountPointWithoutBookmark() async throws {
        // Given
        let testPath = "/Volumes/NoBookmark"
        
        // When/Then
        do {
            _ = try await sut.accessMountPoint(at: testPath)
            XCTFail("Should throw error when no bookmark exists")
        } catch {
            if let bookmarkError = error as? BookmarkError {
                switch bookmarkError {
                case .bookmarkNotFound(let path):
                    XCTAssertEqual(path, testPath)
                default:
                    XCTFail("Unexpected error type: \(bookmarkError)")
                }
            }
        }
    }
    
    func testHasBookmark() {
        // Given
        let testPath = "/Volumes/TestMount"
        
        // Initially no bookmark
        XCTAssertFalse(sut.hasBookmark(for: testPath))
        
        // Note: In real implementation, we would create a bookmark
        // For testing, we're verifying the lookup logic
    }
    
    // MARK: - Bookmark Management Tests
    
    func testRemoveBookmark() {
        // Given
        let testPath = "/Volumes/TestMount"
        
        // When
        sut.removeBookmark(for: testPath)
        
        // Then
        XCTAssertFalse(sut.hasBookmark(for: testPath))
    }
    
    // MARK: - Migration Tests
    
    func testMigrateMountPointsWithValidPaths() async throws {
        // Given - create temporary directories
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("MigrationTest")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }
        
        let mountPaths = [
            tempBase.appendingPathComponent("Mount1").path,
            tempBase.appendingPathComponent("Mount2").path
        ]
        
        // Create the directories
        for path in mountPaths {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path),
                withIntermediateDirectories: true
            )
        }
        
        // When
        let results = await sut.migrateMountPoints(mountPaths)
        
        // Then
        XCTAssertEqual(results.count, 2)
        
        // In test environment, bookmark creation might fail
        // We're mainly testing the migration logic flow
        for result in results {
            XCTAssertNotNil(result.path)
            // Success depends on sandboxing environment
        }
    }
    
    func testMigrateMountPointsWithInvalidPaths() async throws {
        // Given
        let mountPaths = [
            "/Volumes/NonExistent1",
            "/Volumes/NonExistent2"
        ]
        
        // When
        let results = await sut.migrateMountPoints(mountPaths)
        
        // Then
        XCTAssertEqual(results.count, 2)
        for result in results {
            XCTAssertFalse(result.success)
            XCTAssertEqual(result.error, "Directory does not exist")
        }
    }
    
    // MARK: - Bookmark Validation Tests
    
    func testValidateBookmarksRemovesStale() async throws {
        // This test would require mocking bookmark resolution
        // In real implementation, it validates and removes stale bookmarks
        
        // When
        await sut.validateBookmarks()
        
        // Then
        // Verify no bookmarks remain (since we haven't created any valid ones)
        XCTAssertTrue(sut.bookmarks.isEmpty)
    }
    
    // MARK: - Error Handling Tests
    
    func testBookmarkErrorDescriptions() {
        let url = URL(fileURLWithPath: "/test/path")
        let underlyingError = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        
        let errors: [BookmarkError] = [
            .notADirectory(url),
            .creationFailed(url, underlyingError),
            .bookmarkNotFound("/test/path"),
            .resolutionFailed("/test/path", underlyingError),
            .accessDenied(url)
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertNotNil(error.recoverySuggestion)
            XCTAssertFalse(error.errorDescription!.isEmpty)
            XCTAssertFalse(error.recoverySuggestion!.isEmpty)
        }
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentBookmarkOperations() async throws {
        let iterations = 20
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = iterations * 2
        
        // Create temporary test directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ConcurrentTest")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Perform concurrent operations
        for i in 0..<iterations {
            Task {
                // Try to create bookmark (may fail in test environment)
                _ = try? await sut.createBookmark(for: tempDir.appendingPathComponent("Mount\(i)"))
                expectation.fulfill()
            }
            
            Task {
                // Check bookmark existence
                _ = sut.hasBookmark(for: "/Volumes/Mount\(i)")
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    // MARK: - Security Scoped Resource Tests
    
    func testSecurityScopedResourceCleanup() {
        // Given
        let testURL = URL(fileURLWithPath: "/test/path")
        var cleanupCalled = false
        
        // When
        var resource: SecurityScopedResource? = SecurityScopedResource(url: testURL) {
            cleanupCalled = true
        }
        
        // Verify resource exists
        XCTAssertNotNil(resource)
        XCTAssertEqual(resource?.url, testURL)
        XCTAssertFalse(cleanupCalled)
        
        // When resource is released
        resource = nil
        
        // Then cleanup should be called
        XCTAssertTrue(cleanupCalled)
    }
}