#!/bin/bash

# Build script for MacMount
# Supports both development (ad-hoc) and distribution (Developer ID) signing

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building MacMount...${NC}"

# Configuration
APP_NAME="MacMount"
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Build configuration
BUILD_CONFIG="${BUILD_CONFIG:-release}"
SIGNING_MODE="${SIGNING_MODE:-development}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            BUILD_CONFIG="debug"
            shift
            ;;
        --release)
            BUILD_CONFIG="release"
            shift
            ;;
        --sign-development)
            SIGNING_MODE="development"
            shift
            ;;
        --sign-distribution)
            SIGNING_MODE="distribution"
            shift
            ;;
        --team-id)
            export DEVELOPMENT_TEAM_ID="$2"
            shift 2
            ;;
        --identity)
            CUSTOM_IDENTITY="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --debug              Build in debug mode"
            echo "  --release            Build in release mode (default)"
            echo "  --sign-development   Use development signing (default)"
            echo "  --sign-distribution  Use Developer ID signing for distribution"
            echo "  --team-id TEAM_ID    Set development team ID"
            echo "  --identity IDENTITY  Set custom signing identity"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${YELLOW}Build Configuration:${NC}"
echo "  Mode: $BUILD_CONFIG"
echo "  Signing: $SIGNING_MODE"

# Check for required tools
if ! command -v swift &> /dev/null; then
    echo -e "${RED}Error: Swift is not installed${NC}"
    exit 1
fi

if ! command -v codesign &> /dev/null; then
    echo -e "${RED}Error: codesign is not installed${NC}"
    exit 1
fi

# Build the executable
echo -e "${GREEN}Building Swift package...${NC}"
swift build -c "$BUILD_CONFIG"

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
if [ "$BUILD_CONFIG" = "debug" ]; then
    cp .build/debug/MacMount "$MACOS_DIR/$APP_NAME"
else
    cp .build/release/MacMount "$MACOS_DIR/$APP_NAME"
fi

# Strip debug symbols for release builds
if [ "$BUILD_CONFIG" = "release" ]; then
    echo -e "${GREEN}Stripping debug symbols...${NC}"
    strip -S "$MACOS_DIR/$APP_NAME"
fi

# Create Info.plist with proper values
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MacMount</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.macmount</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacMount</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMainStoryboardFile</key>
    <string></string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>MacMount needs to control system events to mount network drives.</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>MacMount needs administrator privileges to mount network drives.</string>
</dict>
</plist>
EOF

# Copy resources
if [ -d "Resources" ]; then
    echo -e "${GREEN}Copying resources...${NC}"
    cp -R Resources/* "$RESOURCES_DIR/"
fi

# Copy entitlements if exists
if [ -f "MacMount.entitlements" ]; then
    cp MacMount.entitlements "$CONTENTS_DIR/"
fi

# Make executable
chmod +x "$MACOS_DIR/$APP_NAME"

# Code signing
echo -e "${GREEN}Signing application...${NC}"

if [ "$SIGNING_MODE" = "distribution" ]; then
    # Distribution signing with Developer ID
    
    # Check for required environment variables
    if [ -z "$DEVELOPMENT_TEAM_ID" ]; then
        echo -e "${YELLOW}Warning: DEVELOPMENT_TEAM_ID not set${NC}"
        echo "Set it with: export DEVELOPMENT_TEAM_ID=XXXXXXXXXX"
    fi
    
    # Determine signing identity
    if [ -n "$CUSTOM_IDENTITY" ]; then
        SIGN_IDENTITY="$CUSTOM_IDENTITY"
    elif [ -n "$CODE_SIGN_IDENTITY_DIST" ]; then
        SIGN_IDENTITY="$CODE_SIGN_IDENTITY_DIST"
    else
        SIGN_IDENTITY="Developer ID Application"
    fi
    
    echo "Using signing identity: $SIGN_IDENTITY"
    
    # Try to find the certificate
    if security find-identity -p codesigning | grep -q "$SIGN_IDENTITY"; then
        echo -e "${GREEN}Found signing certificate${NC}"
        
        # Sign with Developer ID
        codesign --force \
                 --deep \
                 --sign "$SIGN_IDENTITY" \
                 --options runtime \
                 --timestamp \
                 --entitlements "$CONTENTS_DIR/MacMount.entitlements" \
                 "$APP_BUNDLE"
        
        # Verify signature
        echo -e "${GREEN}Verifying signature...${NC}"
        codesign --verify --verbose=2 "$APP_BUNDLE"
        
        # Check for notarization readiness
        echo -e "${GREEN}Checking notarization readiness...${NC}"
        spctl -a -vvv -t install "$APP_BUNDLE"
        
    else
        echo -e "${YELLOW}Warning: Developer ID certificate not found${NC}"
        echo "Falling back to ad-hoc signing..."
        codesign --force --deep --sign - "$APP_BUNDLE"
    fi
    
else
    # Development signing (ad-hoc or Apple Development)
    
    if [ -n "$CUSTOM_IDENTITY" ]; then
        SIGN_IDENTITY="$CUSTOM_IDENTITY"
    elif [ -n "$CODE_SIGN_IDENTITY_DEV" ]; then
        SIGN_IDENTITY="$CODE_SIGN_IDENTITY_DEV"
    else
        SIGN_IDENTITY="-"
    fi
    
    if [ "$SIGN_IDENTITY" = "-" ]; then
        echo "Using ad-hoc signing for development"
        codesign --force --deep --sign - "$APP_BUNDLE"
    else
        echo "Using signing identity: $SIGN_IDENTITY"
        codesign --force \
                 --deep \
                 --sign "$SIGN_IDENTITY" \
                 --entitlements "$CONTENTS_DIR/MacMount.entitlements" \
                 "$APP_BUNDLE"
    fi
fi

echo -e "${GREEN}Build complete!${NC}"
echo "App bundle created at: $APP_BUNDLE"
echo ""
echo "Next steps:"
if [ "$SIGNING_MODE" = "distribution" ]; then
    echo "1. Notarize the app: ./notarize.sh \"$APP_BUNDLE\""
    echo "2. Create DMG for distribution: ./create-dmg.sh"
else
    echo "1. Test the app: open $APP_BUNDLE"
    echo "2. Install to Applications: Scripts/install.sh"
fi