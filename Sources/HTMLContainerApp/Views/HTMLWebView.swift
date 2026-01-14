import SwiftUI
import WebKit

struct HTMLWebView: UIViewRepresentable {
    let url: URL
    var onExit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }

    func makeUIView(context: Context) -> WKWebView {
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
        webView.customUserAgent = "HTMLContainer/1.0 (iPhone; iOS 15)"
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Determine what to load: if url is a folder, load index.html from inside; otherwise load the file directly
        let fileToLoad = resolveFileToLoad(url)
        let accessURL = fileToLoad.deletingLastPathComponent()
        webView.loadFileURL(fileToLoad, allowingReadAccessTo: accessURL)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func resolveFileToLoad(_ url: URL) -> URL {
        var isDir: ObjCBool = false
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            // It's a folder; look for index.html
            let indexURL = url.appendingPathComponent("index.html")
            if fm.fileExists(atPath: indexURL.path) {
                return indexURL
            }
        }
        // It's a file or index.html not found; return as-is
        return url
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
