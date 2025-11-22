#!/bin/bash
# Script to package PingMenubar executable into .app bundle

set -e

# Configuration
APP_NAME="PingMenubar"
BUILD_DIR=".build/release"
BUNDLE_DIR="dist/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building release executable..."
mac swift build -c release

echo "Creating app bundle structure..."
rm -rf dist
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "Copying executable..."
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "Copying icons..."
cp assets/icons/AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
cp assets/icons/menubar-icon.png "${RESOURCES_DIR}/menubar-icon.png"
cp assets/icons/menubar-icon@2x.png "${RESOURCES_DIR}/menubar-icon@2x.png"

echo "Creating Info.plist with proper values..."
sed -e 's/$(EXECUTABLE_NAME)/'"${APP_NAME}"'/g' \
    -e 's/$(PRODUCT_NAME)/'"${APP_NAME}"'/g' \
    Sources/PingMenubar/Info.plist > "${CONTENTS_DIR}/Info.plist"

echo "Creating PkgInfo..."
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo ""
echo "✓ App bundle created at: ${BUNDLE_DIR}"
echo ""
echo "To run:"
echo "  mac open ${BUNDLE_DIR}"
echo ""
echo "To copy to Applications:"
echo "  mac cp -r ${BUNDLE_DIR} /Applications/"
