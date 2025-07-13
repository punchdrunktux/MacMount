//
//  MockFileManager.swift
//  MacMountTests
//
//  Mock FileManager for testing file system operations
//

import Foundation

class MockFileManager {
    var fileExistsResponses: [String: (exists: Bool, isDirectory: Bool)] = [:]
    var createDirectoryError: Error?
    var createdDirectories: [String] = []
    
    func reset() {
        fileExistsResponses.removeAll()
        createDirectoryError = nil
        createdDirectories.removeAll()
    }
    
    func stubFileExists(at path: String, exists: Bool, isDirectory: Bool = false) {
        fileExistsResponses[path] = (exists, isDirectory)
    }
    
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        guard let response = fileExistsResponses[path] else {
            return false
        }
        
        if let isDirectory = isDirectory {
            isDirectory.pointee = ObjCBool(response.isDirectory)
        }
        
        return response.exists
    }
    
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        if let error = createDirectoryError {
            throw error
        }
        createdDirectories.append(url.path)
    }
}

// MARK: - URL Extension for Testing

extension URL {
    /// Creates mock bookmark data for testing
    static func mockBookmarkData(for path: String) -> Data {
        // Create a simple data representation that includes the path
        // This is just for testing - real bookmark data is opaque
        return "MOCK_BOOKMARK:\(path)".data(using: .utf8) ?? Data()
    }
    
    /// Checks if data is mock bookmark data
    static func isMockBookmarkData(_ data: Data) -> Bool {
        guard let string = String(data: data, encoding: .utf8) else { return false }
        return string.hasPrefix("MOCK_BOOKMARK:")
    }
    
    /// Extracts path from mock bookmark data
    static func pathFromMockBookmarkData(_ data: Data) -> String? {
        guard let string = String(data: data, encoding: .utf8),
              string.hasPrefix("MOCK_BOOKMARK:") else { return nil }
        return String(string.dropFirst("MOCK_BOOKMARK:".count))
    }
}