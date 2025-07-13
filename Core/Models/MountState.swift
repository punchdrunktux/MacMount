//
//  MountState.swift
//  MacMount
//
//  Represents the current state of a network drive mount
//

import Foundation

enum MountState: Equatable {
    // Primary states
    case unmounted
    case mounting(attempt: Int, maxAttempts: Int, lastError: MountError? = nil)
    case mounted(health: MountHealth)
    case unmounting
    case error(MountError)
    case disabled // User explicitly disabled
    
    // Mount health sub-states for mounted drives
    enum MountHealth: Equatable {
        case connected      // Mount is functional and server is reachable
        case degraded       // Mount exists but server unreachable (VPN down, network issues)
        case validating     // Currently checking mount health
        case stale          // Mount confirmed non-functional, needs remount
    }
    
    // Legacy stale case for backward compatibility (will be phased out)
    case stale
    
    var isTransitioning: Bool {
        switch self {
        case .mounting(_, _, _), .unmounting:
            return true
        case .mounted(.validating):
            return true
        default:
            return false
        }
    }
    
    var isMounted: Bool {
        switch self {
        case .mounted(_), .stale:
            return true
        default:
            return false
        }
    }
    
    var isHealthy: Bool {
        switch self {
        case .mounted(.connected):
            return true
        default:
            return false
        }
    }
    
    var needsAttention: Bool {
        switch self {
        case .mounted(.degraded), .mounted(.stale), .error(_), .stale:
            return true
        default:
            return false
        }
    }
    
    var displayText: String {
        switch self {
        case .unmounted:
            return "Not Mounted"
        case .mounting(let attempt, let maxAttempts, let lastError):
            if lastError != nil {
                return "Retrying... (attempt \(attempt)/\(maxAttempts))"
            } else {
                return "Mounting... (attempt \(attempt)/\(maxAttempts))"
            }
        case .mounted(let health):
            switch health {
            case .connected:
                return "Connected"
            case .degraded:
                return "Connected (Server Unreachable)"
            case .validating:
                return "Validating Connection..."
            case .stale:
                return "Mount Failed"
            }
        case .unmounting:
            return "Unmounting..."
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        case .disabled:
            return "Disabled"
        case .stale:
            return "Stale Mount" // Legacy
        }
    }
    
    var statusSymbol: String {
        switch self {
        case .unmounted:
            return "circle"
        case .mounting(_, _, let lastError):
            return lastError != nil ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath"
        case .unmounting:
            return "arrow.triangle.2.circlepath"
        case .mounted(let health):
            switch health {
            case .connected:
                return "checkmark.circle.fill"
            case .degraded:
                return "exclamationmark.triangle.fill"
            case .validating:
                return "magnifyingglass.circle"
            case .stale:
                return "xmark.circle.fill"
            }
        case .error:
            return "exclamationmark.circle.fill"
        case .disabled:
            return "nosign"
        case .stale:
            return "exclamationmark.triangle.fill" // Legacy
        }
    }
    
    // MARK: - State Transitions
    
    /// Validates if a state transition is allowed
    func canTransition(to newState: MountState) -> Bool {
        switch (self, newState) {
        // From unmounted
        case (.unmounted, .mounting(_, _, _)):
            return true
        case (.unmounted, .disabled):
            return true
            
        // From mounting
        case (.mounting(_, _, _), .mounted(_)):
            return true
        case (.mounting(_, _, _), .error(_)):
            return true
        case (.mounting(_, _, _), .unmounted):
            return true
        case (.mounting(_, _, _), .disabled):
            return true
            
        // From mounted
        case (.mounted(_), .mounted(_)): // Health state changes
            return true
        case (.mounted(_), .unmounting):
            return true
        case (.mounted(_), .error(_)):
            return true
        case (.mounted(_), .disabled):
            return true
            
        // From unmounting
        case (.unmounting, .unmounted):
            return true
        case (.unmounting, .error(_)):
            return true
            
        // From error
        case (.error(_), .mounting(_, _, _)):
            return true
        case (.error(_), .unmounted):
            return true
        case (.error(_), .disabled):
            return true
            
        // From disabled
        case (.disabled, .unmounted):
            return true
        case (.disabled, .mounting(_, _, _)):
            return true
            
        // Legacy stale transitions
        case (.stale, .mounting(_, _, _)):
            return true
        case (.stale, .unmounted):
            return true
        case (.mounted(_), .stale): // Legacy compatibility
            return true
            
        default:
            return false
        }
    }
    
    /// Returns the appropriate next state for mount success
    static func mountedConnected() -> MountState {
        return .mounted(health: .connected)
    }
    
    /// Returns the appropriate state for a degraded mount (exists but server unreachable)
    static func mountedDegraded() -> MountState {
        return .mounted(health: .degraded)
    }
    
    /// Returns the appropriate state for health validation
    static func mountedValidating() -> MountState {
        return .mounted(health: .validating)
    }
}