# MacMount Makefile

.PHONY: all clean build test release install uninstall

# Configuration
PRODUCT_NAME = MacMount
SCHEME = $(PRODUCT_NAME)
CONFIGURATION_DEBUG = Debug
CONFIGURATION_RELEASE = Release
DERIVED_DATA_PATH = build
ARCHIVE_PATH = $(DERIVED_DATA_PATH)/$(PRODUCT_NAME).xcarchive
APP_PATH = /Applications/$(PRODUCT_NAME).app

# Default target
all: build

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DERIVED_DATA_PATH)
	@xcodebuild clean -scheme $(SCHEME) -configuration $(CONFIGURATION_DEBUG)
	@xcodebuild clean -scheme $(SCHEME) -configuration $(CONFIGURATION_RELEASE)

# Build debug version
build:
	@echo "Building $(PRODUCT_NAME) (Debug)..."
	@xcodebuild build \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION_DEBUG) \
		-derivedDataPath $(DERIVED_DATA_PATH)

# Run tests
test:
	@echo "Running tests..."
	@xcodebuild test \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION_DEBUG) \
		-destination 'platform=macOS'

# Build release version
release:
	@echo "Building $(PRODUCT_NAME) (Release)..."
	@xcodebuild archive \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION_RELEASE) \
		-archivePath $(ARCHIVE_PATH)

# Install to Applications folder
install: release
	@echo "Installing $(PRODUCT_NAME)..."
	@cp -R $(ARCHIVE_PATH)/Products/Applications/$(PRODUCT_NAME).app $(APP_PATH)
	@echo "Installed to $(APP_PATH)"

# Uninstall from Applications folder
uninstall:
	@echo "Uninstalling $(PRODUCT_NAME)..."
	@rm -rf $(APP_PATH)
	@launchctl unload ~/Library/LaunchAgents/com.example.macmount.plist 2>/dev/null || true
	@rm -f ~/Library/LaunchAgents/com.example.macmount.plist
	@echo "Uninstalled"

# Create DMG for distribution
dmg: release
	@echo "Creating DMG..."
	@Scripts/create-dmg.sh

# Notarize the app
notarize: release
	@echo "Notarizing $(PRODUCT_NAME)..."
	@Scripts/notarize.sh

# Run SwiftLint
lint:
	@echo "Running SwiftLint..."
	@swiftlint

# Format code
format:
	@echo "Formatting code..."
	@swift-format -i -r .