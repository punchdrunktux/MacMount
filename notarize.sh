#!/bin/bash

# Notarization script for MacMount
# Submits the app to Apple for notarization and staples the ticket

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if app path is provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No app path provided${NC}"
    echo "Usage: $0 <app-path> [options]"
    echo "Options:"
    echo "  --apple-id EMAIL     Apple ID for notarization"
    echo "  --team-id TEAMID     Team ID (10-character identifier)"
    echo "  --password PASSWORD  App-specific password"
    echo "  --wait               Wait for notarization to complete"
    echo "  --staple-only        Only staple existing notarization"
    exit 1
fi

APP_PATH="$1"
shift

# Default values
WAIT_FOR_NOTARIZATION=false
STAPLE_ONLY=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --apple-id)
            NOTARIZE_APPLE_ID="$2"
            shift 2
            ;;
        --team-id)
            NOTARIZE_TEAM_ID="$2"
            shift 2
            ;;
        --password)
            NOTARIZE_PASSWORD="$2"
            shift 2
            ;;
        --wait)
            WAIT_FOR_NOTARIZATION=true
            shift
            ;;
        --staple-only)
            STAPLE_ONLY=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: App not found at $APP_PATH${NC}"
    exit 1
fi

APP_NAME=$(basename "$APP_PATH" .app)

# Get credentials from environment if not provided
NOTARIZE_APPLE_ID="${NOTARIZE_APPLE_ID:-$NOTARIZE_APPLE_ID}"
NOTARIZE_TEAM_ID="${NOTARIZE_TEAM_ID:-$NOTARIZE_TEAM_ID}"
NOTARIZE_PASSWORD="${NOTARIZE_PASSWORD:-$NOTARIZE_PASSWORD}"

# Staple only mode
if [ "$STAPLE_ONLY" = true ]; then
    echo -e "${GREEN}Stapling notarization ticket...${NC}"
    xcrun stapler staple "$APP_PATH"
    
    echo -e "${GREEN}Verifying stapled ticket...${NC}"
    xcrun stapler validate "$APP_PATH"
    
    echo -e "${GREEN}Notarization ticket stapled successfully!${NC}"
    exit 0
fi

# Check for required credentials
if [ -z "$NOTARIZE_APPLE_ID" ] || [ -z "$NOTARIZE_TEAM_ID" ] || [ -z "$NOTARIZE_PASSWORD" ]; then
    echo -e "${RED}Error: Missing notarization credentials${NC}"
    echo ""
    echo "Required environment variables:"
    echo "  NOTARIZE_APPLE_ID    - Your Apple ID email"
    echo "  NOTARIZE_TEAM_ID     - Your 10-character Team ID"
    echo "  NOTARIZE_PASSWORD    - App-specific password"
    echo ""
    echo "To create an app-specific password:"
    echo "1. Sign in to appleid.apple.com"
    echo "2. Go to Security > App-Specific Passwords"
    echo "3. Click Generate Password"
    echo "4. Use format: xxxx-xxxx-xxxx-xxxx"
    exit 1
fi

echo -e "${BLUE}Notarization Configuration:${NC}"
echo "  App: $APP_NAME"
echo "  Apple ID: $NOTARIZE_APPLE_ID"
echo "  Team ID: $NOTARIZE_TEAM_ID"
echo ""

# Verify the app is signed
echo -e "${GREEN}Verifying app signature...${NC}"
if ! codesign --verify --verbose=2 "$APP_PATH"; then
    echo -e "${RED}Error: App is not properly signed${NC}"
    echo "Sign the app with: ./build-app.sh --sign-distribution"
    exit 1
fi

# Check if signed with Developer ID
if ! codesign -dvv "$APP_PATH" 2>&1 | grep -q "Developer ID Application"; then
    echo -e "${YELLOW}Warning: App is not signed with Developer ID${NC}"
    echo "Notarization requires Developer ID signing"
fi

# Create a temporary directory for the ZIP
TEMP_DIR=$(mktemp -d)
ZIP_PATH="$TEMP_DIR/${APP_NAME}.zip"

# Create ZIP for submission
echo -e "${GREEN}Creating ZIP archive for submission...${NC}"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Submit for notarization
echo -e "${GREEN}Submitting app for notarization...${NC}"
echo "This may take several minutes..."

# Store credentials in keychain (more secure than command line)
# Note: This is optional but recommended for production use
xcrun notarytool store-credentials "NetworkDriveMapper-Notary" \
    --apple-id "$NOTARIZE_APPLE_ID" \
    --team-id "$NOTARIZE_TEAM_ID" \
    --password "$NOTARIZE_PASSWORD" 2>/dev/null || true

# Submit the app
SUBMISSION_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$NOTARIZE_APPLE_ID" \
    --team-id "$NOTARIZE_TEAM_ID" \
    --password "$NOTARIZE_PASSWORD" \
    --wait 2>&1)

# Extract submission ID
SUBMISSION_ID=$(echo "$SUBMISSION_OUTPUT" | grep -E "id: [a-f0-9-]+" | head -1 | awk '{print $2}')

if [ -z "$SUBMISSION_ID" ]; then
    echo -e "${RED}Error: Failed to submit for notarization${NC}"
    echo "$SUBMISSION_OUTPUT"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${GREEN}Submission ID: $SUBMISSION_ID${NC}"

# Wait for notarization if requested
if [ "$WAIT_FOR_NOTARIZATION" = true ]; then
    echo -e "${YELLOW}Waiting for notarization to complete...${NC}"
    
    # Poll for status
    while true; do
        STATUS_OUTPUT=$(xcrun notarytool info "$SUBMISSION_ID" \
            --apple-id "$NOTARIZE_APPLE_ID" \
            --team-id "$NOTARIZE_TEAM_ID" \
            --password "$NOTARIZE_PASSWORD" 2>&1)
        
        if echo "$STATUS_OUTPUT" | grep -q "status: Accepted"; then
            echo -e "${GREEN}Notarization succeeded!${NC}"
            break
        elif echo "$STATUS_OUTPUT" | grep -q "status: Invalid"; then
            echo -e "${RED}Notarization failed!${NC}"
            
            # Get the log for debugging
            echo -e "${YELLOW}Fetching notarization log...${NC}"
            xcrun notarytool log "$SUBMISSION_ID" \
                --apple-id "$NOTARIZE_APPLE_ID" \
                --team-id "$NOTARIZE_TEAM_ID" \
                --password "$NOTARIZE_PASSWORD"
            
            rm -rf "$TEMP_DIR"
            exit 1
        elif echo "$STATUS_OUTPUT" | grep -q "status: In Progress"; then
            echo -n "."
            sleep 30
        else
            echo -e "${YELLOW}Unknown status, continuing to wait...${NC}"
            sleep 30
        fi
    done
    
    # Staple the ticket
    echo -e "${GREEN}Stapling notarization ticket...${NC}"
    xcrun stapler staple "$APP_PATH"
    
    echo -e "${GREEN}Verifying stapled ticket...${NC}"
    xcrun stapler validate "$APP_PATH"
    
else
    echo -e "${YELLOW}Notarization submitted successfully!${NC}"
    echo ""
    echo "To check status:"
    echo "  xcrun notarytool info $SUBMISSION_ID --apple-id $NOTARIZE_APPLE_ID --team-id $NOTARIZE_TEAM_ID"
    echo ""
    echo "Once notarization is complete, staple the ticket:"
    echo "  ./notarize.sh \"$APP_PATH\" --staple-only"
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo -e "${GREEN}Done!${NC}"