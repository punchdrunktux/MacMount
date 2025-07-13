# MacMount

A native macOS menu bar application that automatically mounts and manages network drives (AFP, SMB, NFS) with intelligent reconnection capabilities.

## Features

- 🖥️ **Native Menu Bar App**: Runs quietly in your menu bar without cluttering the dock
- 🔌 **Multi-Protocol Support**: Works with AFP, SMB, and NFS network shares
- 🔄 **Automatic Reconnection**: Intelligently remounts drives when network becomes available
- 🔐 **Secure Credential Storage**: Uses macOS Keychain for hardware-encrypted password storage
- 🌐 **VPN-Aware**: Automatically mounts drives when VPN connects
- 💤 **Sleep/Wake Handling**: Gracefully handles system sleep and wake cycles
- ⚡ **Performance Optimized**: Minimal resource usage with < 50MB memory footprint
- 🛡️ **Resilient**: Circuit breaker pattern prevents excessive retry attempts

## Requirements

- macOS 12.0 (Monterey) or later
- Network access to file servers
- Administrator access for initial setup

## Installation

1. Download the latest release from the Releases page
2. Open the DMG file
3. Drag MacMount to your Applications folder
4. Launch MacMount from Applications
5. Grant necessary permissions when prompted

The app will automatically start at login after first launch.

## Building from Source

### Prerequisites

- Xcode 14.0 or later
- Swift 5.9 or later
- Developer ID certificate for code signing

### Build Steps

```bash
# Clone the repository
git clone https://github.com/yourusername/MacMount.git
cd MacMount

# Build the app
xcodebuild -project MacMount.xcodeproj \
           -scheme MacMount \
           -configuration Release \
           -derivedDataPath build

# Run tests
xcodebuild test -project MacMount.xcodeproj \
                -scheme MacMount \
                -destination 'platform=macOS'
```

## Architecture

MacMount uses a modern Swift architecture:

- **SwiftUI** for the user interface
- **Combine** for reactive state management
- **Swift Concurrency** (async/await) for networking
- **Actors** for thread-safe service layer
- **Network.framework** for network monitoring
- **Security.framework** for Keychain integration

## License

This project is licensed under the MIT License - see the LICENSE file for details.
