# Makefile for PingMenubar macOS app

# Configuration
APP_NAME = PingMenubar
BUNDLE_ID = com.pingmenubar.app
BUILD_DIR = .build
DIST_DIR = dist
APP_BUNDLE = $(DIST_DIR)/$(APP_NAME).app
SWIFT = mac swift
XCODEBUILD = mac /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
WORKSPACE = .swiftpm/xcode/package.xcworkspace

# Targets
.PHONY: all build build-release test package clean install run help

# Default target
all: package

# Build debug version
build:
	@echo "Building debug version..."
	$(SWIFT) build

# Build release version
build-release:
	@echo "Building release version..."
	$(SWIFT) build -c release

# Run unit tests
test:
	@echo "Running tests..."
	$(XCODEBUILD) test \
		-workspace $(WORKSPACE) \
		-scheme $(APP_NAME)-Package \
		-destination 'platform=macOS'

# Create .app bundle
package: build-release
	@echo "Packaging $(APP_NAME).app..."
	@rm -rf $(DIST_DIR)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@chmod +x $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp assets/icons/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@cp assets/icons/menubar-icon.png $(APP_BUNDLE)/Contents/Resources/menubar-icon.png
	@cp assets/icons/menubar-icon@2x.png $(APP_BUNDLE)/Contents/Resources/menubar-icon@2x.png
	@sed -e 's/$$(EXECUTABLE_NAME)/$(APP_NAME)/g' \
	     -e 's/$$(PRODUCT_NAME)/$(APP_NAME)/g' \
	     Sources/PingMenubar/Info.plist > $(APP_BUNDLE)/Contents/Info.plist
	@echo -n "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo
	@echo "✓ App bundle created at: $(APP_BUNDLE)"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@rm -rf $(DIST_DIR)
	@echo "✓ Clean complete"

# Install to /Applications
install: package
	@echo "Installing to /Applications..."
	mac sudo rm -rf /Applications/$(APP_NAME).app
	mac sudo cp -r $(APP_BUNDLE) /Applications/
	@echo "✓ Installed to /Applications/$(APP_NAME).app"

# Run the app from dist
run: package
	@echo "Launching $(APP_NAME)..."
	mac open $(APP_BUNDLE)

# Run the app from /Applications if installed
run-installed:
	@echo "Launching installed $(APP_NAME)..."
	mac open /Applications/$(APP_NAME).app

# Build and run debug version
dev:
	@echo "Building and running debug version..."
	$(SWIFT) build
	mac $(BUILD_DIR)/debug/$(APP_NAME)

# Show help
help:
	@echo "PingMenubar Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  make              - Build and package release .app bundle (default)"
	@echo "  make build        - Build debug version"
	@echo "  make build-release- Build release version"
	@echo "  make test         - Run unit tests"
	@echo "  make package      - Create .app bundle in dist/"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make install      - Install to /Applications"
	@echo "  make run          - Package and run the app"
	@echo "  make run-installed- Run app from /Applications"
	@echo "  make dev          - Build and run debug version (no bundle)"
	@echo "  make help         - Show this help message"
