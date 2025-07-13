# Bundle Configuration Documentation

## Overview

This document describes the bundle configuration for MacMount, including all metadata, identifiers, and settings required for proper distribution.

## Bundle Identifier

**Production**: `com.example.macmount.app`

This identifier is used throughout the application:
- Main app bundle identifier
- Launch agent identifier
- Keychain service name prefix
- URL scheme registration

## Version Information

- **CFBundleShortVersionString**: 1.0.0 (user-visible version)
- **CFBundleVersion**: 1 (build number)

## App Metadata

### Display Information
- **CFBundleDisplayName**: MacMount
- **CFBundleName**: MacMount
- **Copyright**: Copyright © 2025 MacMount. All rights reserved.

### App Store Category
- **LSApplicationCategoryType**: public.app-category.utilities

## Privacy and Permissions

The following usage descriptions are configured for system privacy prompts:

1. **NSAppleEventsUsageDescription**: For sending Apple Events to mount drives
2. **NSSystemAdministrationUsageDescription**: For admin privileges to mount drives
3. **NSNetworkVolumesUsageDescription**: For accessing network volumes
4. **NSRemovableVolumesUsageDescription**: For accessing removable volumes
5. **NSDesktopFolderUsageDescription**: For creating mount shortcuts on Desktop
6. **NSDocumentsFolderUsageDescription**: For creating mount shortcuts in Documents
7. **NSDownloadsFolderUsageDescription**: For saving diagnostic logs

## App Configuration

### Menu Bar App
- **LSUIElement**: true (runs as menu bar app without dock icon)

### Termination Behavior
- **NSSupportsAutomaticTermination**: false
- **NSSupportsSuddenTermination**: false

### Display Settings
- **NSHighResolutionCapable**: true (supports Retina displays)
- **NSRequiresAquaSystemAppearance**: false (supports Dark Mode)

## URL Scheme

The app registers the `macmount://` URL scheme for:
- Deep linking from web documentation
- Automation and scripting
- Quick actions from other apps

## Launch Agent Configuration

The launch agent (`com.example.macmount.app.LaunchAgent.plist`) provides:
- Automatic startup at login
- Process management
- Error logging to `/tmp/com.example.macmount.app.err`
- Output logging to `/tmp/com.example.macmount.app.out`

## Icon Configuration

App icons are configured in `Resources/Assets.xcassets/AppIcon.appiconset/` with all required sizes:
- 16x16 (1x, 2x)
- 32x32 (1x, 2x)
- 128x128 (1x, 2x)
- 256x256 (1x, 2x)
- 512x512 (1x, 2x)

## Sparkle Update Framework

Configured for automatic updates:
- **SUEnableAutomaticChecks**: true
- **SUFeedURL**: https://macmount.app/appcast.xml
- **SUPublicEDKey**: [Needs to be generated]

## Build Configuration

Key build settings in `BuildConfig.xcconfig`:
- **PRODUCT_BUNDLE_IDENTIFIER**: com.example.macmount.app
- **MACOSX_DEPLOYMENT_TARGET**: 12.0
- **ENABLE_APP_SANDBOX**: YES
- **ENABLE_HARDENED_RUNTIME**: YES

## Updating Bundle Information

When preparing for release:

1. Update version numbers in Info.plist
2. Generate and add Sparkle public key
3. Create proper app icons
4. Update copyright year if needed
5. Verify all usage descriptions are accurate
6. Test URL scheme functionality
7. Validate launch agent configuration