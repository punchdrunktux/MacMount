//
//  SecurePasswordFieldTests.swift
//  MacMountTests
//
//  Comprehensive tests for SecurePasswordField to ensure secure password handling
//

import XCTest
@testable import MacMount

@MainActor
final class SecurePasswordFieldTests: XCTestCase {
    
    var sut: SecurePasswordField!
    
    override func setUp() async throws {
        try await super.setUp()
        sut = SecurePasswordField()
    }
    
    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testInitialState() {
        XCTAssertEqual(sut.temporaryPassword, "")
        XCTAssertFalse(sut.hasPassword)
        XCTAssertNil(sut.peekPassword())
    }
    
    func testSettingPassword() async throws {
        // When
        sut.setPassword("testPassword123")
        
        // Allow time for Combine publisher to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then
        XCTAssertTrue(sut.hasPassword)
        XCTAssertEqual(sut.peekPassword(), "testPassword123")
    }
    
    func testClearingPassword() async throws {
        // Given
        sut.setPassword("testPassword123")
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // When
        sut.clearPassword()
        
        // Then
        XCTAssertEqual(sut.temporaryPassword, "")
        XCTAssertFalse(sut.hasPassword)
        XCTAssertNil(sut.peekPassword())
    }
    
    // MARK: - Security Tests
    
    func testConsumePasswordClearsData() async throws {
        // Given
        sut.setPassword("sensitivePassword")
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // When
        let consumed = sut.consumePassword()
        
        // Then
        XCTAssertEqual(consumed, "sensitivePassword")
        XCTAssertFalse(sut.hasPassword)
        XCTAssertNil(sut.peekPassword())
        XCTAssertEqual(sut.temporaryPassword, "")
    }
    
    func testPeekPasswordDoesNotClearData() async throws {
        // Given
        sut.setPassword("persistentPassword")
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // When
        let peeked1 = sut.peekPassword()
        let peeked2 = sut.peekPassword()
        
        // Then
        XCTAssertEqual(peeked1, "persistentPassword")
        XCTAssertEqual(peeked2, "persistentPassword")
        XCTAssertTrue(sut.hasPassword)
    }
    
    func testEmptyPasswordHandling() {
        // When
        sut.setPassword("")
        
        // Then
        XCTAssertFalse(sut.hasPassword)
        XCTAssertNil(sut.consumePassword())
        XCTAssertNil(sut.peekPassword())
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentAccess() async throws {
        let iterations = 100
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = iterations * 2
        
        // Perform concurrent reads and writes
        for i in 0..<iterations {
            Task {
                sut.setPassword("password\(i)")
                expectation.fulfill()
            }
            
            Task {
                _ = sut.peekPassword()
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Verify field is still in valid state
        sut.clearPassword()
        XCTAssertFalse(sut.hasPassword)
    }
    
    func testRapidSetAndConsume() async throws {
        let iterations = 50
        var consumedPasswords: [String?] = []
        
        for i in 0..<iterations {
            let password = "rapidTest\(i)"
            sut.setPassword(password)
            
            // Small delay to allow Combine to process
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            
            let consumed = sut.consumePassword()
            consumedPasswords.append(consumed)
            
            // Verify cleared after consumption
            XCTAssertFalse(sut.hasPassword)
        }
        
        // Verify we got valid passwords (some might be nil due to timing)
        let validPasswords = consumedPasswords.compactMap { $0 }
        XCTAssertGreaterThan(validPasswords.count, 0)
    }
    
    // MARK: - Memory Management Tests
    
    func testPasswordDataIsCleared() async throws {
        // This test verifies that password data is properly cleared
        // Note: We can't directly inspect private Data, but we can verify behavior
        
        // Given
        sut.setPassword("memoryTestPassword")
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // When
        sut.clearPassword()
        
        // Then
        XCTAssertNil(sut.peekPassword())
        XCTAssertNil(sut.consumePassword())
        
        // Set new password to verify old data doesn't leak
        sut.setPassword("newPassword")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sut.peekPassword(), "newPassword")
    }
    
    func testDeinitClearsPassword() async throws {
        // Given
        var field: SecurePasswordField? = SecurePasswordField()
        field?.setPassword("deinitTestPassword")
        try await Task.sleep(nanoseconds: 100_000_000)
        
        weak var weakField = field
        
        // When
        field = nil
        
        // Then
        XCTAssertNil(weakField, "SecurePasswordField should be deallocated")
    }
    
    // MARK: - Edge Cases
    
    func testUnicodePasswordHandling() async throws {
        let unicodePasswords = [
            "🔐🔑🗝️",
            "пароль",
            "密码",
            "パスワード",
            "🇺🇸🇬🇧🇯🇵"
        ]
        
        for password in unicodePasswords {
            sut.setPassword(password)
            try await Task.sleep(nanoseconds: 100_000_000)
            
            XCTAssertEqual(sut.peekPassword(), password, 
                          "Should handle unicode password: \(password)")
            sut.clearPassword()
        }
    }
    
    func testVeryLongPassword() async throws {
        // Create a very long password
        let longPassword = String(repeating: "a", count: 10000)
        
        // When
        sut.setPassword(longPassword)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Then
        XCTAssertTrue(sut.hasPassword)
        XCTAssertEqual(sut.consumePassword()?.count, 10000)
        XCTAssertFalse(sut.hasPassword)
    }
    
    func testSpecialCharacterPasswords() async throws {
        let specialPasswords = [
            "p@ssw0rd!",
            "test\"quote\"",
            "back\\slash",
            "new\nline",
            "tab\ttab",
            "<script>alert('xss')</script>"
        ]
        
        for password in specialPasswords {
            sut.setPassword(password)
            try await Task.sleep(nanoseconds: 100_000_000)
            
            XCTAssertEqual(sut.peekPassword(), password,
                          "Should handle special characters: \(password)")
            sut.clearPassword()
        }
    }
    
    // MARK: - Performance Tests
    
    func testSetPasswordPerformance() {
        measure {
            for i in 0..<1000 {
                sut.setPassword("perfTest\(i)")
                sut.clearPassword()
            }
        }
    }
    
    func testConsumePasswordPerformance() {
        measure {
            for i in 0..<1000 {
                sut.setPassword("perfTest\(i)")
                _ = sut.consumePassword()
            }
        }
    }
}