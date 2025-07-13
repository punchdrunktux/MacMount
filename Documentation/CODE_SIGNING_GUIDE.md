# Code Signing Guide for MacMount

This guide explains how to properly sign MacMount for development and distribution.

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Development Signing](#development-signing)
4. [Distribution Signing](#distribution-signing)
5. [Environment Variables](#environment-variables)
6. [CI/CD Integration](#cicd-integration)
7. [Troubleshooting](#troubleshooting)

## Overview

MacMount supports two signing modes:
- **Development**: For local testing (ad-hoc or Apple Development certificate)
- **Distribution**: For public release (Developer ID certificate + notarization)

## Prerequisites

### Required Tools
- Xcode Command Line Tools
- Valid Apple Developer account (for distribution)
- Developer ID Application certificate (for distribution)

### Check Available Certificates
```bash
# List all code signing certificates
security find-identity -p codesigning

# Check for Developer ID certificates specifically
security find-identity -p codesigning | grep "Developer ID Application"
```

## Development Signing

### Ad-hoc Signing (No Certificate Required)
```bash
# Default behavior - uses ad-hoc signing
./build-app.sh

# Explicitly specify development mode
./build-app.sh --sign-development
```

### Apple Development Certificate
```bash
# If you have an Apple Development certificate
export CODE_SIGN_IDENTITY_DEV="Apple Development: Your Name (XXXXXXXXXX)"
./build-app.sh --sign-development
```

## Distribution Signing

### Step 1: Configure Environment
```bash
# Set your team ID (found in Apple Developer account)
export DEVELOPMENT_TEAM_ID="XXXXXXXXXX"

# Set your signing identity (optional if you have only one)
export CODE_SIGN_IDENTITY_DIST="Developer ID Application: Your Name (XXXXXXXXXX)"

# Set notarization credentials
export NOTARIZE_APPLE_ID="your@email.com"
export NOTARIZE_TEAM_ID="XXXXXXXXXX"
export NOTARIZE_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # App-specific password
```

### Step 2: Build with Distribution Signing
```bash
# Build for distribution
./build-app.sh --sign-distribution

# Or specify team ID directly
./build-app.sh --sign-distribution --team-id "XXXXXXXXXX"
```

### Step 3: Notarize the App
```bash
# Submit for notarization and wait
./notarize.sh NetworkDriveMapper.app --wait

# Or submit without waiting
./notarize.sh NetworkDriveMapper.app
```

### Step 4: Create Distribution DMG
```bash
# Create signed and notarized DMG
./create-dmg.sh --sign --notarize

# Or create DMG without signing
./create-dmg.sh
```

## Environment Variables

### Build Configuration

| Variable | Description | Example |
|----------|-------------|---------|
| `DEVELOPMENT_TEAM_ID` | Your Apple Developer Team ID | `XXXXXXXXXX` |
| `CODE_SIGN_IDENTITY_DEV` | Development signing identity | `Apple Development` or `-` |
| `CODE_SIGN_IDENTITY_DIST` | Distribution signing identity | `Developer ID Application` |
| `BUILD_CONFIG` | Build configuration | `debug` or `release` |
| `SIGNING_MODE` | Signing mode | `development` or `distribution` |

### Notarization Configuration

| Variable | Description | How to Get |
|----------|-------------|------------|
| `NOTARIZE_APPLE_ID` | Your Apple ID email | Your developer account email |
| `NOTARIZE_TEAM_ID` | Team ID for notarization | Same as `DEVELOPMENT_TEAM_ID` |
| `NOTARIZE_PASSWORD` | App-specific password | Generate at appleid.apple.com |

### Creating an App-Specific Password
1. Sign in to [appleid.apple.com](https://appleid.apple.com)
2. Go to Security → App-Specific Passwords
3. Click Generate Password
4. Name it "MacMount Notarization"
5. Save the password (format: `xxxx-xxxx-xxxx-xxxx`)

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Build and Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Configure Signing
      env:
        DEVELOPMENT_TEAM_ID: ${{ secrets.DEVELOPMENT_TEAM_ID }}
        CODE_SIGN_IDENTITY_DIST: ${{ secrets.CODE_SIGN_IDENTITY }}
        NOTARIZE_APPLE_ID: ${{ secrets.NOTARIZE_APPLE_ID }}
        NOTARIZE_TEAM_ID: ${{ secrets.NOTARIZE_TEAM_ID }}
        NOTARIZE_PASSWORD: ${{ secrets.NOTARIZE_PASSWORD }}
      run: |
        # Import signing certificate from secrets
        echo "${{ secrets.SIGNING_CERTIFICATE_P12 }}" | base64 --decode > certificate.p12
        security create-keychain -p "${{ secrets.KEYCHAIN_PASSWORD }}" build.keychain
        security default-keychain -s build.keychain
        security unlock-keychain -p "${{ secrets.KEYCHAIN_PASSWORD }}" build.keychain
        security import certificate.p12 -k build.keychain -P "${{ secrets.P12_PASSWORD }}" -T /usr/bin/codesign
        security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${{ secrets.KEYCHAIN_PASSWORD }}" build.keychain
    
    - name: Build and Sign
      run: |
        ./build-app.sh --sign-distribution --release
    
    - name: Notarize
      run: |
        ./notarize.sh MacMount.app --wait
    
    - name: Create DMG
      run: |
        ./create-dmg.sh --sign --notarize
    
    - name: Upload Release
      uses: actions/upload-artifact@v3
      with:
        name: MacMount-Release
        path: MacMount-*.dmg
```

### Local Build Configuration

Create a `BuildConfig.local.xcconfig` file (git-ignored) for local overrides:
```xcconfig
// BuildConfig.local.xcconfig
// Local development configuration (not committed to git)

DEVELOPMENT_TEAM = YOUR_ACTUAL_TEAM_ID
CODE_SIGN_IDENTITY_DEV = Apple Development: Your Name (XXXXXXXXXX)
CODE_SIGN_IDENTITY_DIST = Developer ID Application: Your Name (XXXXXXXXXX)
```

## Troubleshooting

### Common Issues

#### "Developer ID Application" certificate not found
```bash
# Check exact certificate name
security find-identity -p codesigning -v

# Use the exact name in quotes
export CODE_SIGN_IDENTITY_DIST="Developer ID Application: John Doe (ABC1234567)"
```

#### Notarization fails with "invalid credentials"
- Ensure you're using an app-specific password, not your Apple ID password
- Verify the Apple ID has access to the Developer account
- Check that the Team ID matches your certificate

#### "App is damaged and can't be opened"
This occurs when:
- App is not properly signed
- App is not notarized
- Gatekeeper quarantine flag is set

Fix:
```bash
# Remove quarantine flag (for testing only)
xattr -d com.apple.quarantine MacMount.app

# Verify signature
codesign --verify --verbose=2 MacMount.app
spctl -a -vvv -t install MacMount.app
```

#### Build fails with "no identity found"
Ensure environment variables are exported:
```bash
# Check current environment
env | grep -E "(TEAM_ID|SIGN_IDENTITY)"

# Export in current shell
export DEVELOPMENT_TEAM_ID="XXXXXXXXXX"

# Or add to ~/.zshrc for persistence
echo 'export DEVELOPMENT_TEAM_ID="XXXXXXXXXX"' >> ~/.zshrc
source ~/.zshrc
```

### Verification Commands

```bash
# Verify app signature
codesign --verify --deep --verbose=2 MacMount.app

# Check entitlements
codesign -d --entitlements - MacMount.app

# Verify notarization
xcrun stapler validate MacMount.app

# Test Gatekeeper acceptance
spctl -a -vvv -t install MacMount.app
```

## Security Best Practices

1. **Never commit credentials** to version control
2. **Use environment variables** or CI/CD secrets for sensitive data
3. **Rotate app-specific passwords** regularly
4. **Test thoroughly** on clean macOS installations
5. **Keep certificates secure** with strong keychain passwords

## Additional Resources

- [Apple Developer - Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Introduction/Introduction.html)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)