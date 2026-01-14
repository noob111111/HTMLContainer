import Foundation

/// Instructions to integrate Chromium for iOS sideloading:
/// 
/// Option 1: Use a prebuilt Chromium framework
/// - Download chromium-ios arm64 binary from: https://github.com/GoogleChromeLabs/chromium-ios-builds
/// - Extract the framework: Chromium.framework
/// - Add to Xcode: Targets > HTMLContainer > Build Phases > Link Binary With Libraries
/// - Add framework search path: $(PROJECT_DIR)/Frameworks
///
/// Option 2: Build Chromium from source (requires significant setup)
/// - Clone https://github.com/chromium/chromium (iOS branch)
/// - Build with: gn gen out/ios && ninja -C out/ios
/// - Extract the resulting Chromium.framework
///
/// Option 3: Use CEF (Chromium Embedded Framework)
/// - Download CEF iOS build from: https://bitbucket.org/chromiumembedded/cef/wiki/BranchesAndBuilding
/// - Link CEF libraries instead of Chromium.framework
///
/// Once integrated, uncomment the import below and use ChromiumWebEngine

// Uncomment when Chromium framework is available:
// import Chromium

/// Flag to detect if Chromium is available
let chromiumAvailable: Bool = {
    #if CHROMIUM_AVAILABLE
    return true
    #else
    return false
    #endif
}()
