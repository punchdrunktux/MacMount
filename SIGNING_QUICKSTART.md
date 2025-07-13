# Code Signing Quick Start Guide

## For Developers (Local Testing)

No certificates required! Just build and run:

```bash
# Build with ad-hoc signing (default)
./build-app.sh

# Install to Applications
../Scripts/install.sh
```

## For Distribution

### 1. First Time Setup

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your credentials
nano .env

# Load environment
./setup-env.sh
```

### 2. Required Credentials

Edit `.env` and set:
- `DEVELOPMENT_TEAM_ID`: Your 10-character Team ID from [developer.apple.com](https://developer.apple.com)
- `NOTARIZE_APPLE_ID`: Your Apple ID email
- `NOTARIZE_PASSWORD`: App-specific password from [appleid.apple.com](https://appleid.apple.com)

### 3. Build and Sign

```bash
# Load environment variables
source .env-export.tmp

# Build with distribution signing
./build-app.sh --sign-distribution

# Notarize the app
./notarize.sh MacMount.app --wait

# Create DMG for distribution
./create-dmg.sh --sign --notarize
```

## Common Commands

```bash
# Check available certificates
security find-identity -p codesigning

# Verify app signature
codesign --verify --verbose MacMount.app

# Check notarization
xcrun stapler validate MacMount.app

# Test Gatekeeper
spctl -a -vvv MacMount.app
```

## Troubleshooting

### "Certificate not found"
- Run `security find-identity -p codesigning` to see exact certificate names
- Update `.env` with the exact certificate name

### "Invalid credentials" during notarization
- Ensure you're using an app-specific password, not your Apple ID password
- Generate one at: appleid.apple.com → Security → App-Specific Passwords

### Build fails
- Check that Xcode Command Line Tools are installed: `xcode-select --install`
- Ensure Swift is available: `swift --version`

## CI/CD Integration

Set these secrets in your CI/CD system:
- `DEVELOPMENT_TEAM_ID`
- `NOTARIZE_APPLE_ID`
- `NOTARIZE_TEAM_ID`
- `NOTARIZE_PASSWORD`
- `SIGNING_CERTIFICATE_P12` (base64 encoded)
- `P12_PASSWORD`

See [CODE_SIGNING_GUIDE.md](Documentation/CODE_SIGNING_GUIDE.md) for detailed setup.