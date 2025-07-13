//
//  XCTestCase+Async.swift
//  MacMountTests
//
//  Async/await test helpers and utilities
//

import XCTest

extension XCTestCase {
    /// Waits for an async condition to become true
    /// - Parameters:
    ///   - timeout: Maximum time to wait
    ///   - condition: Async closure that returns true when condition is met
    /// - Throws: XCTestError if timeout is exceeded
    func waitForCondition(
        timeout: TimeInterval = 5.0,
        condition: @escaping () async -> Bool
    ) async throws {
        let start = Date()
        
        while Date().timeIntervalSince(start) < timeout {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        XCTFail("Condition not met within \(timeout) seconds")
    }
    
    /// Asserts that an async operation throws a specific error
    /// - Parameters:
    ///   - expression: Async throwing expression
    ///   - error: Expected error type
    ///   - message: Failure message
    func assertAsyncThrows<T, E: Error & Equatable>(
        _ expression: @autoclosure () async throws -> T,
        error expectedError: E,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error \(expectedError) but no error was thrown. \(message)", 
                   file: file, line: line)
        } catch let thrownError as E {
            XCTAssertEqual(thrownError, expectedError, message, file: file, line: line)
        } catch {
            XCTFail("Expected error \(expectedError) but got \(error). \(message)", 
                   file: file, line: line)
        }
    }
    
    /// Measures async operation performance
    /// - Parameters:
    ///   - block: Async operation to measure
    func measureAsync(_ block: () async throws -> Void) {
        measure {
            let expectation = expectation(description: "async measure")
            
            Task {
                do {
                    try await block()
                } catch {
                    XCTFail("Async measure block threw error: \(error)")
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 60.0)
        }
    }
}

/// Test helper for memory leak detection
extension XCTestCase {
    /// Tracks an object and verifies it's deallocated after the test
    /// - Parameter object: Object to track
    func trackForMemoryLeaks(_ object: AnyObject, 
                            file: StaticString = #filePath, 
                            line: UInt = #line) {
        addTeardownBlock { [weak object] in
            XCTAssertNil(object, "Instance should have been deallocated", 
                        file: file, line: line)
        }
    }
}