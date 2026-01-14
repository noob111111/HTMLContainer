# Chromium Integration Guide

HTMLContainer is set up to use **Chromium as the rendering engine** for iOS sideload (no App Store restrictions).

## Quick Start

### Automatic Setup (Recommended)

```bash
cd scripts
bash setup-chromium.sh
```

This will:
- Download the latest Chromium arm64 build
- Extract it to `Frameworks/Chromium.framework`
- Print Xcode configuration steps

### Manual Setup

1. **Download Chromium**
   - Visit: https://github.com/GoogleChromeLabs/chromium-ios-builds/releases
   - Download the latest `chromium-ios-arm64.zip` (arm64 for physical devices, not simulators)

2. **Extract Framework**
   ```bash
   unzip chromium-ios-arm64.zip
   mkdir -p Frameworks
   mv Chromium.framework Frameworks/
   ```

3. **Configure Xcode**
   - Open `HTMLContainer.xcodeproj`
   - Go to **Targets > HTMLContainer > Build Settings**
   - Search for "Framework Search Paths"
   - Add: `$(PROJECT_DIR)/Frameworks`
   - Search for "Other Linker Flags"
   - Add: `-framework Chromium`
   - Search for "Swift Compiler - Custom Flags"
   - Add: `-DCHROMIUM_AVAILABLE=1`

4. **Enable in Code**
   - Open `Sources/HTMLContainerApp/Views/ChromiumWebView.swift`
   - Uncomment the line: `// import Chromium`
   - Open `Sources/HTMLContainerApp/Utils/ChromiumConfig.swift`
   - Update CHROMIUM_AVAILABLE check

## Alternative Approaches

### Option 1: Build Chromium from Source
```bash
git clone https://github.com/chromium/chromium.git
cd chromium
gn gen out/ios --args='target_os="ios" target_cpu="arm64"'
ninja -C out/ios
```

### Option 2: Use CEF (Chromium Embedded Framework)
- Download from: https://bitbucket.org/chromiumembedded/cef/wiki/BranchesAndBuilding
- Link CEF libraries instead of Chromium.framework

## Verification

After integration, the app will:
- Use native Chromium rendering (not WebKit)
- Display as "Chrome/131.0" in user agent
- Support all Chromium features (WebGL, Service Workers, etc.)

## Troubleshooting

### "Chromium/Chromium.h not found"
- Ensure `Frameworks/Chromium.framework` exists
- Check Build Settings > Framework Search Paths includes `$(PROJECT_DIR)/Frameworks`

### Simulator Build Fails
- Chromium arm64 is for physical devices only
- For simulator testing, use the WKWebView fallback (no Chromium framework needed)

### Linking Errors
- Verify `Chromium.framework` is added to "Link Binary With Libraries"
- Check "Other Linker Flags" includes `-framework Chromium`

## Legal Notes

- Chromium source: BSPL + MIT licensed (see chromium/LICENSE)
- For commercial use, review the license terms
- Sideload distribution is unrestricted under current regulations (Japan MSCA, EU DMA)
