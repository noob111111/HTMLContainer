#!/usr/bin/env bash
# Build HTMLOpener.ipa on macOS (needs Xcode command line tools + ldid:  brew install ldid)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build; APP=$OUT/Payload/HTMLOpener.app
rm -rf "$OUT"; mkdir -p "$APP"

xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0 \
  -fobjc-arc -fmodules -O2 \
  -Wno-deprecated-declarations -Wno-unguarded-availability-new \
  -framework UIKit -framework WebKit -framework SafariServices \
  -framework UniformTypeIdentifiers -framework Foundation \
  Sources/HTMLOpener.m -o "$APP/HTMLOpener"

cp Resources/Info.plist "$APP/Info.plist"
cp Resources/Icons/*.png "$APP/"
printf 'APPL????' > "$APP/PkgInfo"

# Pseudo-sign with the entitlements. TrollStore / LiveContainer / AltStore re-sign or accept this.
ldid -SResources/Entitlements.plist "$APP/HTMLOpener"

( cd "$OUT" && zip -qr HTMLOpener.ipa Payload )
echo "Built $OUT/HTMLOpener.ipa"
