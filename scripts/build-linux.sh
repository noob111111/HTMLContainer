#!/usr/bin/env bash
# Cross-compile on Linux. Needs: clang + lld, ldid, zip, and an iPhoneOS SDK (e.g. iPhoneOS16.5.sdk).
#   SDK=/path/to/iPhoneOS16.5.sdk ./scripts/build-linux.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SDK:?set SDK to the path of an iPhoneOS .sdk}"
LDID=${LDID:-ldid}
OUT=build; APP=$OUT/Payload/HTMLOpener.app
rm -rf "$OUT"; mkdir -p "$APP"

clang -target arm64-apple-ios15.0 -isysroot "$SDK" \
  -fobjc-arc -fmodules -O2 -fuse-ld=lld \
  -Wno-deprecated-declarations -Wno-unguarded-availability-new \
  -framework UIKit -framework WebKit -framework SafariServices \
  -framework UniformTypeIdentifiers -framework Foundation \
  Sources/HTMLOpener.m -o "$APP/HTMLOpener"

cp Resources/Info.plist "$APP/Info.plist"
cp Resources/Icons/*.png "$APP/"
printf 'APPL????' > "$APP/PkgInfo"
"$LDID" -SResources/Entitlements.plist "$APP/HTMLOpener"
( cd "$OUT" && zip -qr HTMLOpener.ipa Payload )
echo "Built $OUT/HTMLOpener.ipa"
