#!/bin/bash

# Environment setup script for MacMount
# Sources environment variables from .env file

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${BLUE}MacMount Environment Setup${NC}"
echo "===================================="
echo ""

# Check if .env exists
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo -e "${YELLOW}No .env file found!${NC}"
    echo ""
    
    if [ -f "$SCRIPT_DIR/.env.example" ]; then
        echo "Creating .env from template..."
        cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
        echo -e "${GREEN}Created .env file${NC}"
        echo ""
        echo -e "${YELLOW}Please edit .env and fill in your credentials:${NC}"
        echo "  $SCRIPT_DIR/.env"
        echo ""
        echo "Then run this script again."
        exit 1
    else
        echo -e "${RED}Error: No .env.example file found${NC}"
        exit 1
    fi
fi

# Source the .env file
echo -e "${GREEN}Loading environment from .env...${NC}"
export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)

# Validate required variables
MISSING_VARS=()

# Check development team
if [ -z "$DEVELOPMENT_TEAM_ID" ] || [ "$DEVELOPMENT_TEAM_ID" = "XXXXXXXXXX" ]; then
    MISSING_VARS+=("DEVELOPMENT_TEAM_ID")
fi

# Check notarization credentials for distribution
if [ "$SIGNING_MODE" = "distribution" ]; then
    if [ -z "$NOTARIZE_APPLE_ID" ] || [ "$NOTARIZE_APPLE_ID" = "your@email.com" ]; then
        MISSING_VARS+=("NOTARIZE_APPLE_ID")
    fi
    
    if [ -z "$NOTARIZE_TEAM_ID" ] || [ "$NOTARIZE_TEAM_ID" = "XXXXXXXXXX" ]; then
        MISSING_VARS+=("NOTARIZE_TEAM_ID")
    fi
    
    if [ -z "$NOTARIZE_PASSWORD" ] || [ "$NOTARIZE_PASSWORD" = "xxxx-xxxx-xxxx-xxxx" ]; then
        MISSING_VARS+=("NOTARIZE_PASSWORD")
    fi
fi

# Report missing variables
if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Warning: The following variables need to be configured:${NC}"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "Edit $SCRIPT_DIR/.env to set these values."
    echo ""
fi

# Display current configuration
echo -e "${BLUE}Current Configuration:${NC}"
echo "  Team ID: ${DEVELOPMENT_TEAM_ID:-Not set}"
echo "  Build Config: ${BUILD_CONFIG:-release}"
echo "  Signing Mode: ${SIGNING_MODE:-development}"

if [ -n "$CODE_SIGN_IDENTITY_DEV" ] && [ "$CODE_SIGN_IDENTITY_DEV" != "-" ]; then
    echo "  Dev Identity: $CODE_SIGN_IDENTITY_DEV"
fi

if [ -n "$CODE_SIGN_IDENTITY_DIST" ] && [ "$CODE_SIGN_IDENTITY_DIST" != "Developer ID Application" ]; then
    echo "  Dist Identity: $CODE_SIGN_IDENTITY_DIST"
fi

# Check for signing certificates
echo ""
echo -e "${BLUE}Checking signing certificates...${NC}"

if [ "$SIGNING_MODE" = "distribution" ]; then
    # Check for Developer ID certificate
    if security find-identity -p codesigning | grep -q "${CODE_SIGN_IDENTITY_DIST}"; then
        echo -e "${GREEN}✓ Distribution certificate found${NC}"
    else
        echo -e "${YELLOW}⚠ Distribution certificate not found${NC}"
        echo "  Looking for: $CODE_SIGN_IDENTITY_DIST"
        echo ""
        echo "Available certificates:"
        security find-identity -p codesigning -v | grep "Developer ID" || echo "  No Developer ID certificates found"
    fi
else
    # Check for development certificate
    if [ "$CODE_SIGN_IDENTITY_DEV" != "-" ]; then
        if security find-identity -p codesigning | grep -q "${CODE_SIGN_IDENTITY_DEV}"; then
            echo -e "${GREEN}✓ Development certificate found${NC}"
        else
            echo -e "${YELLOW}⚠ Development certificate not found${NC}"
            echo "  Will use ad-hoc signing"
        fi
    else
        echo -e "${GREEN}✓ Using ad-hoc signing for development${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Environment setup complete!${NC}"
echo ""
echo "You can now run:"
echo "  ./build-app.sh                    # Build with current settings"
echo "  ./build-app.sh --sign-distribution # Build for distribution"
echo ""

# Create a temporary script to export variables
cat > "$SCRIPT_DIR/.env-export.tmp" << 'EOF'
# Source this file to export environment variables
# Usage: source .env-export.tmp

EOF

grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^$' | while IFS='=' read -r key value; do
    echo "export $key=\"$value\"" >> "$SCRIPT_DIR/.env-export.tmp"
done

echo "To export these variables to your current shell:"
echo "  source $SCRIPT_DIR/.env-export.tmp"
echo ""