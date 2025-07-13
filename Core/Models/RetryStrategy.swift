//
//  RetryStrategy.swift
//  MacMount
//
//  Defines retry behavior for failed mount attempts
//

import Foundation

enum RetryStrategy: String, CaseIterable, Codable {
    case aggressive = "aggressive"
    case normal = "normal"
    case conservative = "conservative"
    case manual = "manual"
    
    var displayName: String {
        switch self {
        case .aggressive:
            return "Aggressive (5s)"
        case .normal:
            return "Normal (30s)"
        case .conservative:
            return "Conservative (5m)"
        case .manual:
            return "Manual Only"
        }
    }
    
    var baseInterval: TimeInterval {
        switch self {
        case .aggressive:
            return 5
        case .normal:
            return 30
        case .conservative:
            return 300
        case .manual:
            return .infinity
        }
    }
    
    var maxRetries: Int {
        switch self {
        case .aggressive:
            return 10
        case .normal:
            return 5
        case .conservative:
            return 3
        case .manual:
            return 1  // At least try once, even for manual
        }
    }
    
    var backoffMultiplier: Double {
        switch self {
        case .aggressive:
            return 1.5
        case .normal:
            return 2.0
        case .conservative:
            return 3.0
        case .manual:
            return 1.0
        }
    }
    
    func delayForRetry(_ retryCount: Int) -> TimeInterval {
        guard self != .manual else { return .infinity }
        
        let exponentialDelay = baseInterval * pow(backoffMultiplier, Double(min(retryCount, 4)))
        let jitter = Double.random(in: 0.8...1.2)
        let maxDelay: TimeInterval = 600 // 10 minutes
        
        return min(exponentialDelay * jitter, maxDelay)
    }
}