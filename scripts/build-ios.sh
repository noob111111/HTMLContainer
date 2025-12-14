#!/usr/bin/env bash
set -euo pipefail

# Send all output to build.log and stdout/stderr
exec > >(tee build.log) 2>&1

echo "=== HTMLContainer iOS build script ==="
echo "Started: $(date)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found; attempting to install via brew"
  brew install xcodegen || true
fi

echo "Generating Xcode project with xcodegen..."
xcodegen generate
echo "xcodegen complete"

set -x
echo "Running xcodebuild..."
xcodebuild -project HTMLContainer.xcodeproj -scheme HTMLContainer -configuration Release -sdk iphoneos BUILD_DIR=build CODE_SIGNING_ALLOWED=NO clean build

APP_PATH=$(ls build/Release-iphoneos/*.app 2>/dev/null | head -n1 || true)
if [ -z "$APP_PATH" ]; then
  echo "ERROR: .app not found in build output"
  exit 2
fi

echo "Found app at: $APP_PATH"
mkdir -p Payload
rm -rf Payload/*
cp -R "$APP_PATH" Payload/
zip -r HTMLContainer.ipa Payload

echo "IPA created: $(pwd)/HTMLContainer.ipa"
echo "Finished: $(date)"
