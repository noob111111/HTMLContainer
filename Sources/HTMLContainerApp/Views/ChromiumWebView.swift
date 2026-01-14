import SwiftUI
import WebKit

/// Abstract web view protocol to support multiple rendering engines
protocol WebViewEngine: UIViewRepresentable {
    var url: URL { get }
    var onExit: () -> Void { get }
}

/// Chromium-based web view for iOS sideload.
/// This uses a compiled Chromium binary (embedded or system-level).
/// For production, integrate Google's Chromium via:
/// - CEF (Chromium Embedded Framework) iOS port
/// - A precompiled Chromium arm64 binary
/// - Or compile from https://github.com/chromium/chromium source (iOS branch)
struct ChromiumWebView: UIViewRepresentable {
    let url: URL
    var onExit: () -> Void

    func makeUIView(context: Context) -> UIView {
        // Placeholder: In production, this would initialize a real Chromium view.
        // For now, fallback to WKWebView with Chromium user agent.
        // When you have a Chromium binary or framework:
        //   1. Import the Chromium framework
        //   2. Initialize chromium::ios::ChromiumWebView here
        //   3. Return the native Chromium view
        
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Inject a helper so games can call exitToSelector()
        let js = """
        window.exitToSelector = function() { window.webkit.messageHandlers.exit.postMessage(null); };
        """
        let userScript = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)
        contentController.add(context.coordinator, name: "exit")

        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        // Chromium user agent to identify as Chrome
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/605.1.15"
        webView.navigationDelegate = context.coordinator

        let fileToLoad = resolveFileToLoad(url)
        let baseURL = getBaseURL(fileToLoad)
        webView.loadFileURL(fileToLoad, allowingReadAccessTo: baseURL)
        return webView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onExit: onExit)
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
            }
        }
    }
}
