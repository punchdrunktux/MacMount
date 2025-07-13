//
//  RetryManager.swift
//  MacMount
//
//  Retry logic with circuit breaker pattern
//

import Foundation

actor RetryManager {
    private var failureCounts: [UUID: Int] = [:]
    private var lastFailureTimes: [UUID: Date] = [:]
    private var retryAttempts: [UUID: Int] = [:] // Track current retry attempt
    private var lastSuccessfulMount: [UUID: Date] = [:] // Track when server was last successfully mounted
    private let maxFailures = 5
    private let resetInterval: TimeInterval = 300 // 5 minutes
    
    func shouldRetry(for serverId: UUID) -> Bool {
        let failures = failureCounts[serverId] ?? 0
        
        // Check if circuit should be reset
        if let lastFailure = lastFailureTimes[serverId],
           Date().timeIntervalSince(lastFailure) > resetInterval {
            failureCounts[serverId] = 0
            lastFailureTimes[serverId] = nil
            return true
        }
        
        return failures < maxFailures
    }
    
    func recordSuccess(for serverId: UUID) {
        failureCounts[serverId] = 0
        lastFailureTimes[serverId] = nil
        retryAttempts[serverId] = 0
        lastSuccessfulMount[serverId] = Date()
    }
    
    func recordFailure(for serverId: UUID) {
        failureCounts[serverId] = (failureCounts[serverId] ?? 0) + 1
        lastFailureTimes[serverId] = Date()
        retryAttempts[serverId] = (retryAttempts[serverId] ?? 0) + 1
    }
    
    func getCurrentRetryAttempt(for serverId: UUID) -> Int {
        return retryAttempts[serverId] ?? 0
    }
    
    func nextRetryDelay(for serverId: UUID, strategy: RetryStrategy, customInterval: TimeInterval? = nil) -> TimeInterval? {
        guard shouldRetry(for: serverId) else { return nil }
        
        let failures = failureCounts[serverId] ?? 0
        let baseDelay = customInterval ?? strategy.baseInterval
        
        // For custom intervals, use simpler backoff
        if customInterval != nil {
            // Simple linear backoff for custom intervals
            let delay = baseDelay * Double(min(failures + 1, 3))
            let jitter = Double.random(in: 0.9...1.1)
            return min(delay * jitter, 120) // Cap at 2 minutes for custom
        } else {
            // Exponential backoff for strategy-based intervals
            let exponentialDelay = baseDelay * pow(strategy.backoffMultiplier, Double(min(failures, 4)))
            let jitter = Double.random(in: 0.8...1.2)
            return min(exponentialDelay * jitter, 600) // Cap at 10 minutes
        }
    }
    
    func reset() {
        failureCounts.removeAll()
        lastFailureTimes.removeAll()
        retryAttempts.removeAll()
        // Keep lastSuccessfulMount as it's useful history
    }
    
    func reset(for serverId: UUID) {
        failureCounts.removeValue(forKey: serverId)
        lastFailureTimes.removeValue(forKey: serverId)
        retryAttempts.removeValue(forKey: serverId)
    }
    
    // Clear all retry states on network change
    func clearAllRetryStates() {
        failureCounts.removeAll()
        lastFailureTimes.removeAll()
        retryAttempts.removeAll()
    }
    
    // Check if server was recently successful (for prioritization)
    func wasRecentlySuccessful(serverId: UUID, within: TimeInterval = 3600) -> Bool {
        guard let lastSuccess = lastSuccessfulMount[serverId] else { return false }
        return Date().timeIntervalSince(lastSuccess) < within
    }
}