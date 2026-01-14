import Foundation

/// Chromium Integration for iOS (Optional)
///
/// The app works out-of-the-box with WKWebView. Chromium integration is OPTIONAL for enhanced features.
/// Since true Chromium binaries are very large (300+MB), they are not bundled by default.
///
/// To add Chromium support to a custom build:
/// 1. Download Chromium.framework (see CHROMIUM.md)
/// 2. Add to project: Targets > Build Settings > Framework Search Paths: $(PROJECT_DIR)/Frameworks
/// 3. Link: Other Linker Flags: -framework Chromium
/// 4. Define: SWIFT_DEFINES: CHROMIUM_AVAILABLE=1
/// 5. Uncomment import in ChromiumWebView.swift
///
/// For the standard IPA distribution, WKWebView with Chrome user-agent is sufficient.

// Uncomment when Chromium framework is linked:
// import Chromium

/// Flag to detect if Chromium is available (only true if manually integrated)
let chromiumAvailable: Bool = {
    #if CHROMIUM_AVAILABLE
    return true
    #else
    return false
    #endif
}()

