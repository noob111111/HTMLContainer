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

APP_PATH=$(find build/Release-iphoneos -maxdepth 1 -name "*.app" -print -quit || true)
if [ -z "$APP_PATH" ]; then
  echo "ERROR: .app not found in build output (tried build/Release-iphoneos)"
  echo "Listing build/Release-iphoneos contents:"
  ls -la build/Release-iphoneos || true
  exit 2
fi

echo "Found app at: $APP_PATH"
mkdir -p Payload
rm -rf Payload/* || true
echo "Copying app into Payload/"
cp -R "$APP_PATH" Payload/ || { echo "cp failed"; ls -la "$(dirname "$APP_PATH")"; exit 2; }
echo "Payload contents:" && ls -la Payload || true

echo "Creating IPA archive..."
zip -r HTMLContainer.ipa Payload || { echo "zip failed"; ls -la; exit 2; }

echo "IPA created: $(pwd)/HTMLContainer.ipa"
echo "Finished: $(date)"
