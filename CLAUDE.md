# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is MacMount - a native macOS menu bar utility that automatically mounts and manages network drives (AFP, SMB, NFS) with intelligent reconnection capabilities.



## 🎯 Development Philosophy
### Core Principles

- No Quick Fixes: All implementations must be architecturally sound and sustainable long-term
- Production-Ready: Every change should be production-grade, not a temporary workaround
- Future-Proof: Consider scalability, maintainability, and extensibility in every decision
- Clean Architecture: Maintain separation of concerns and follow SOLID principles

## Decision Framework
When implementing any feature or fix:

Analyze the root cause, not just symptoms
Consider impact on existing architecture
Evaluate multiple solutions before choosing
Document architectural decisions and trade-offs
Ensure backward compatibility where applicable

## Architecture

### Core Components
- **Menu Bar UI Layer**: SwiftUI-based menu bar interface with status item, popover, and preferences window
- **Application Core**: MountCoordinator, NetworkMonitor, VPNMonitor for orchestration
- **Service Layer**: MountService, CredentialManager, ConfigService for core functionality
- **System Integration**: NetFS.framework, Keychain Services, UserDefaults

### Key Design Patterns
- Coordinator pattern for orchestration
- Repository pattern for data access
- Actor pattern for thread-safe operations
- ObservableObject/Published for state management

## Development Commands

### Build
```bash
xcodebuild -project MacMount.xcodeproj \
           -scheme Release \
           -configuration Release \
           -derivedDataPath build
```

### Test
```bash
# Unit tests
xcodebuild test -project MacMount.xcodeproj \
                -scheme MacMount \
                -destination 'platform=macOS'

# UI tests
xcodebuild test -project MacMount.xcodeproj \
                -scheme MacMountUITests \
                -destination 'platform=macOS'
```

### Code Quality
```bash
# SwiftLint for code style
swiftlint

# Swift format
swift-format -i -r Sources/
```

## Key Implementation Details

### Security
- Credentials stored in hardware-encrypted macOS Keychain
- No sensitive data in memory longer than necessary
- Code signing and notarization required for distribution

### Networking
- Uses Network.framework for monitoring
- Supports AFP, SMB, and NFS protocols
- VPN-aware mounting with NetworkExtension.framework

### Error Handling
- Comprehensive error types with recovery suggestions
- Circuit breaker pattern for retry logic
- Automatic crash recovery on startup

### Performance
- < 50MB memory footprint target
- Efficient background monitoring
- Battery optimization for low power mode

## Testing Strategy
- Unit tests for all service layer components
- Integration tests for network operations
- UI tests for user flows
- Mock implementations for testability

## Important Notes
- Non-sandboxed application (requires full disk access)
- Minimum macOS 12.0 (Monterey) requirement
- Swift 5.9+ with modern concurrency features
- Uses async/await throughout