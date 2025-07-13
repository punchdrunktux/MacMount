#!/bin/bash

# DMG Creation Script for MacMount
# Creates a distributable DMG with the notarized app

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="MacMount"
DMG_NAME="${APP_NAME}-1.0.0"
VOLUME_NAME="MacMount Installer"
DMG_SIZE="50m"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --app-path)
            APP_PATH="$2"
            shift 2
            ;;
        --output)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --sign)
            SIGN_DMG=true
            shift
            ;;
        --identity)
            DMG_SIGN_IDENTITY="$2"
            shift 2
            ;;
        --notarize)
            NOTARIZE_DMG=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --app-path PATH      Path to the app bundle (default: MacMount.app)"
            echo "  --output PATH        Output DMG path (default: MacMount-1.0.0.dmg)"
            echo "  --sign               Sign the DMG with Developer ID"
            echo "  --identity IDENTITY  Signing identity for DMG (default: Developer ID Application)"
            echo "  --notarize           Submit DMG for notarization after creation"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Default values
APP_PATH="${APP_PATH:-${APP_NAME}.app}"
OUTPUT_PATH="${OUTPUT_PATH:-${DMG_NAME}.dmg}"
DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-Developer ID Application}"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: App not found at $APP_PATH${NC}"
    echo "Build the app first with: ./build-app.sh --sign-distribution"
    exit 1
fi

# Check if app is notarized
echo -e "${GREEN}Checking app notarization status...${NC}"
if ! xcrun stapler validate "$APP_PATH" 2>/dev/null; then
    echo -e "${YELLOW}Warning: App is not notarized${NC}"
    echo "Notarize the app first with: ./notarize.sh \"$APP_PATH\" --wait"
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
MOUNT_DIR="$TEMP_DIR/dmg"

echo -e "${GREEN}Creating DMG for ${APP_NAME}...${NC}"

# Create the DMG source folder
mkdir -p "$MOUNT_DIR"

# Copy app to DMG source
echo "Copying app to DMG source..."
cp -R "$APP_PATH" "$MOUNT_DIR/"

# Create Applications symlink
ln -s /Applications "$MOUNT_DIR/Applications"

# Create background directory
mkdir -p "$MOUNT_DIR/.background"

# Create a simple install instructions file
cat > "$MOUNT_DIR/Install Instructions.txt" << EOF
NetworkDriveMapper Installation Instructions
==========================================

1. Drag NetworkDriveMapper to the Applications folder
2. Double-click NetworkDriveMapper in Applications to launch
3. Grant necessary permissions when prompted
4. Configure your network drives in Preferences

For more information, visit:
https://github.com/yourusername/networkdrivemapper

Thank you for using NetworkDriveMapper!
EOF

# Create temporary DMG
TEMP_DMG="$TEMP_DIR/temp.dmg"
echo -e "${GREEN}Creating temporary DMG...${NC}"
hdiutil create -srcfolder "$MOUNT_DIR" \
               -volname "$VOLUME_NAME" \
               -fs HFS+ \
               -fsargs "-c c=64,a=16,e=16" \
               -format UDRW \
               -size "$DMG_SIZE" \
               "$TEMP_DMG"

# Mount the temporary DMG
echo -e "${GREEN}Mounting temporary DMG...${NC}"
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG" | \
         grep -E '^/dev/' | awk '{print $1}')
MOUNT_POINT=$(mount | grep "$DEVICE" | awk '{print $3}')

# Wait for mount
sleep 2

# Set custom icon positions and window properties using AppleScript
echo -e "${GREEN}Setting DMG window properties...${NC}"
osascript << EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 900, 400}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set position of item "NetworkDriveMapper.app" of container window to {125, 150}
        set position of item "Applications" of container window to {375, 150}
        set position of item "Install Instructions.txt" of container window to {250, 250}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

# Unmount the temporary DMG
echo -e "${GREEN}Unmounting temporary DMG...${NC}"
hdiutil detach "$DEVICE" -quiet

# Convert to compressed DMG
echo -e "${GREEN}Creating final DMG...${NC}"
hdiutil convert "$TEMP_DMG" \
                -format UDZO \
                -imagekey zlib-level=9 \
                -o "$OUTPUT_PATH"

# Sign the DMG if requested
if [ "$SIGN_DMG" = true ]; then
    echo -e "${GREEN}Signing DMG...${NC}"
    
    # Check if signing identity exists
    if security find-identity -p codesigning | grep -q "$DMG_SIGN_IDENTITY"; then
        codesign --force \
                 --sign "$DMG_SIGN_IDENTITY" \
                 --timestamp \
                 "$OUTPUT_PATH"
        
        echo -e "${GREEN}DMG signed successfully${NC}"
    else
        echo -e "${YELLOW}Warning: Signing identity not found, skipping DMG signing${NC}"
    fi
fi

# Notarize the DMG if requested
if [ "$NOTARIZE_DMG" = true ]; then
    echo -e "${GREEN}Submitting DMG for notarization...${NC}"
    ./notarize.sh "$OUTPUT_PATH" --wait
fi

# Verify the final DMG
echo -e "${GREEN}Verifying DMG...${NC}"
hdiutil verify "$OUTPUT_PATH"

# Cleanup
rm -rf "$TEMP_DIR"

# Calculate size
DMG_SIZE=$(du -h "$OUTPUT_PATH" | awk '{print $1}')

echo -e "${GREEN}DMG created successfully!${NC}"
echo ""
echo "Output: $OUTPUT_PATH"
echo "Size: $DMG_SIZE"
echo ""
echo "Distribution checklist:"
echo "✓ App is code signed with Developer ID"
echo "✓ App is notarized and stapled"
echo "✓ DMG is created and compressed"
if [ "$SIGN_DMG" = true ]; then
    echo "✓ DMG is code signed"
fi
if [ "$NOTARIZE_DMG" = true ]; then
    echo "✓ DMG is notarized"
fi
echo ""
echo "The DMG is ready for distribution!"