import SwiftUI
import WebKit

// Uncomment when Chromium framework is linked:
// import Chromium

/// Chromium-based web view for iOS sideload.
/// Automatically uses native Chromium when available, falls back to WKWebView with Chromium user agent.
struct ChromiumWebView: UIViewRepresentable {
    let url: URL
    var onExit: () -> Void

    func makeUIView(context: Context) -> UIView {
        // Try to use native Chromium first
        #if CHROMIUM_AVAILABLE
        // Initialize actual Chromium view when framework is linked
        // Example (adjust based on actual Chromium API):
        // let chromiumView = ChromiumViewController()
        // chromiumView.loadURL(url)
        // return chromiumView.view
        #endif
        
        // Fallback: WKWebView with Chromium-like behavior
        return makeWKWebView(context: context)
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onExit: onExit)
    }

    private func makeWKWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Inject a helper so games can call exitToSelector()
        let js = """
        window.exitToSelector = function() { window.webkit.messageHandlers.exit.postMessage(null); };
        window.console.log = function(msg) { window.webkit.messageHandlers.console.postMessage(msg); };
        """
        let userScript = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)
        contentController.add(context.coordinator, name: "exit")
        contentController.add(context.coordinator, name: "console")

        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        // Chromium user agent to identify as Chrome (for websites that require it)
        // webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/605.1.15"
        webView.navigationDelegate = context.coordinator

        let fileToLoad = resolveFileToLoad(url)
        let baseURL = getBaseURL(fileToLoad)
        print("Loading file: \(fileToLoad), baseURL: \(baseURL)")
        webView.loadFileURL(fileToLoad, allowingReadAccessTo: baseURL)
        
        // Temporary debug: wait 20 seconds, write log, then exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            let logURL = url.deletingLastPathComponent().appendingPathComponent("debug.log")
            let logContent = """
            Loaded file: \(url.path)
            Resolved file: \(fileToLoad.path)
            Base URL: \(baseURL.path)
            Timestamp: \(Date())
            """
            do {
                try logContent.write(to: logURL, atomically: true, encoding: .utf8)
                print("Wrote debug log to: \(logURL.path)")
            } catch {
                print("Failed to write debug log: \(error)")
            }
            context.coordinator.onExit()
        }
        
        return webView
    }

    private func resolveFileToLoad(_ url: URL) -> URL {
        var isDir: ObjCBool = false
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            let indexURL = url.appendingPathComponent("index.html")
            if fm.fileExists(atPath: indexURL.path) {
                return indexURL
            }
        }
        return url
    }

    private func getBaseURL(_ fileURL: URL) -> URL {
        var isDir: ObjCBool = false
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
            return fileURL
        }
        return fileURL.deletingLastPathComponent()
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onExit: () -> Void
        init(onExit: @escaping () -> Void) { self.onExit = onExit }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "exit" {
                DispatchQueue.main.async { self.onExit() }
            } else if message.name == "console" {
                print("WebView console: \(message.body)")
            }
        }
    }
}
