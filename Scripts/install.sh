#!/bin/bash
#
# NetworkDriveMapper Installation Script
# Installs the app preserving code signature and notarization
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

APP_NAME="MacMount"
APP_PATH="/Applications/${APP_NAME}.app"
LAUNCH_AGENT_PLIST="com.example.macmount.plist"
LAUNCH_AGENT_PATH="${HOME}/Library/LaunchAgents/${LAUNCH_AGENT_PLIST}"

echo -e "${BLUE}Installing ${APP_NAME}...${NC}"

# Parse command line arguments
SOURCE_APP="${APP_NAME}.app"
SKIP_LAUNCH_AGENT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --app-path)
            SOURCE_APP="$2"
            shift 2
            ;;
        --skip-launch-agent)
            SKIP_LAUNCH_AGENT=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --app-path PATH      Path to the app to install (default: MacMount.app)"
            echo "  --skip-launch-agent  Don't create launch agent"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Check if app exists
if [ ! -d "$SOURCE_APP" ]; then
    echo -e "${RED}Error: $SOURCE_APP not found${NC}"
    echo "Build the app first with: ./build-app.sh"
    exit 1
fi

# Check if app is signed
echo -e "${GREEN}Checking app signature...${NC}"
if codesign --verify --verbose=2 "$SOURCE_APP" 2>&1 | grep -q "valid on disk"; then
    echo -e "${GREEN}✓ App signature is valid${NC}"
    
    # Check if notarized
    if xcrun stapler validate "$SOURCE_APP" 2>/dev/null; then
        echo -e "${GREEN}✓ App is notarized${NC}"
    else
        echo -e "${YELLOW}⚠ App is not notarized${NC}"
        echo "  For distribution, notarize with: ./notarize.sh \"$SOURCE_APP\""
    fi
else
    echo -e "${YELLOW}⚠ App is not properly signed${NC}"
fi

# Check if app is already installed
if [ -d "$APP_PATH" ]; then
    echo -e "${YELLOW}Existing installation found${NC}"
    
    # Check if it's running
    if pgrep -x "$APP_NAME" > /dev/null; then
        echo "Stopping running instance..."
        killall "$APP_NAME" 2>/dev/null || true
        sleep 2
    fi
    
    # Remove old installation
    echo "Removing old installation..."
    rm -rf "$APP_PATH"
fi

# Copy app to Applications (preserving signatures)
echo -e "${GREEN}Installing app to Applications folder...${NC}"
cp -R "$SOURCE_APP" "$APP_PATH"

# Verify installation preserved signature
if ! codesign --verify --verbose=2 "$APP_PATH" 2>&1 | grep -q "valid on disk"; then
    echo -e "${RED}Error: Installation corrupted app signature${NC}"
    exit 1
fi

# Don't modify permissions as it can break signatures
# The app should already have correct permissions from build

# Create launch agent if not skipped
if [ "$SKIP_LAUNCH_AGENT" = false ]; then
    # Create LaunchAgents directory if it doesn't exist
    mkdir -p "${HOME}/Library/LaunchAgents"

    # Create launch agent plist
    echo -e "${GREEN}Creating launch agent...${NC}"
    cat > "${LAUNCH_AGENT_PATH}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.macmount</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP_PATH}/Contents/MacOS/${APP_NAME}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

    # Load launch agent
    echo -e "${GREEN}Loading launch agent...${NC}"
    if launchctl load "${LAUNCH_AGENT_PATH}" 2>/dev/null; then
        echo -e "${GREEN}✓ Launch agent loaded${NC}"
    else
        echo -e "${YELLOW}⚠ Launch agent may already be loaded${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""

if [ "$SKIP_LAUNCH_AGENT" = false ]; then
    echo "${APP_NAME} has been installed and will start automatically at login."
else
    echo "${APP_NAME} has been installed."
fi

echo "You can launch it from: ${APP_PATH}"

# Offer to open the app
echo ""
read -p "Would you like to open ${APP_NAME} now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Opening ${APP_NAME}...${NC}"
    open "$APP_PATH"
fi