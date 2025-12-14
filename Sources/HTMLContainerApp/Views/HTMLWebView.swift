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

        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

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
