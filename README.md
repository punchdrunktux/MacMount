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

## Usage

### Adding a Network Drive

1. Click the MacMount icon in your menu bar
2. Select "Preferences..."
3. Click the "+" button to add a new server
4. Fill in the server details:
   - Protocol (SMB, AFP, or NFS)
   - Server address
   - Share name
   - Username and password (optional)
   - Mount options
5. Click "Save"

### Managing Drives

- **Mount/Unmount**: Click the menu bar icon and select a drive to toggle
- **Edit Configuration**: Open Preferences and double-click a server
- **Remove Server**: Select a server in Preferences and click "-"

### Advanced Options

- **Requires VPN**: Only mount when specific VPN is connected
- **Hidden Mount**: Hide drive from Finder sidebar
- **Read Only**: Mount drive in read-only mode
- **Retry Strategy**: Configure how aggressively to retry failed mounts

## Security

MacMount takes security seriously:

- Credentials are stored in the macOS Keychain with hardware encryption
- No passwords are stored in plain text
- App is code-signed and notarized by Apple
- Minimal permissions required (no sandboxing to allow mount operations)

## Troubleshooting

### Drive Won't Mount

1. Verify server is accessible: `ping server-address`
2. Check credentials are correct
3. Ensure share name is spelled correctly
4. Check firewall settings

### App Won't Start at Login

1. Open System Settings > General > Login Items
2. Add MacMount to the list
3. Ensure it's enabled

### Collecting Diagnostics

1. Click the menu bar icon
2. Hold Option and click "About"
3. Click "Export Diagnostics..."
4. Share the generated file for support

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

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Thanks to the macOS developer community
- Icon designed by [Designer Name]
- Inspired by the need for better network drive management on macOS