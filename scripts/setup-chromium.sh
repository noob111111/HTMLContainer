#!/bin/bash

# Chromium Integration Helper for iOS Sideload
# This script helps download and set up Chromium for the HTMLContainer app

set -e

CHROMIUM_DOWNLOAD_URL="https://github.com/GoogleChromeLabs/chromium-ios-builds/releases/download/latest/chromium-ios-arm64.zip"
FRAMEWORKS_DIR="$(pwd)/Frameworks"
CHROMIUM_FRAMEWORK="$FRAMEWORKS_DIR/Chromium.framework"

echo "🔧 HTMLContainer Chromium Integration"
echo "======================================"

# Check if we already have Chromium
if [ -d "$CHROMIUM_FRAMEWORK" ]; then
    echo "✅ Chromium.framework already exists at $CHROMIUM_FRAMEWORK"
    exit 0
fi

echo "📦 Downloading Chromium for iOS (arm64)..."
echo "Note: This may take several minutes (~200-300 MB)"

# Create Frameworks directory
mkdir -p "$FRAMEWORKS_DIR"

# Download Chromium
if command -v curl &> /dev/null; then
    curl -L -o "$FRAMEWORKS_DIR/chromium.zip" "$CHROMIUM_DOWNLOAD_URL"
else
    echo "❌ curl not found. Please install curl or manually download from:"
    echo "   $CHROMIUM_DOWNLOAD_URL"
    exit 1
fi

echo "📂 Extracting Chromium..."
unzip -q "$FRAMEWORKS_DIR/chromium.zip" -d "$FRAMEWORKS_DIR"
rm "$FRAMEWORKS_DIR/chromium.zip"

if [ -d "$CHROMIUM_FRAMEWORK" ]; then
    echo "✅ Chromium.framework successfully installed!"
    echo ""
    echo "📋 Next steps:"
    echo "1. Open HTMLContainer.xcodeproj in Xcode"
    echo "2. Go to Targets > HTMLContainer > Build Settings"
    echo "3. Search for 'Framework Search Paths'"
    echo "4. Add: \$(PROJECT_DIR)/Frameworks"
    echo "5. Search for 'Other Linker Flags'"
    echo "6. Add: -framework Chromium"
    echo ""
    echo "To use Chromium in code:"
    echo "- Uncomment the 'import Chromium' line in ChromiumWebView.swift"
    echo "- Set the CHROMIUM_AVAILABLE build flag in Build Settings"
else
    echo "❌ Failed to extract Chromium.framework"
    exit 1
fi
