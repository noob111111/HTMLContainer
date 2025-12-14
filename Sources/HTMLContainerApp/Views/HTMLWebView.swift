import SwiftUI
import WebKit

struct HTMLWebView: UIViewRepresentable {
    let url: URL
    var onExit: () -> Void
    var onLoad: (() -> Void)? = nil
    var onError: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit, onLoad: onLoad, onError: onError) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Inject a helper so games can call exitToSelector()
        let js = """
        window.exitToSelector = function() { window.webkit.messageHandlers.exit.postMessage(null); };
        """
        let userScript = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)
        // Forward console messages to the app so we can persist them to a log file
        let consoleJS = """
        (function(){
            const send = function(level, args){
                try {
                    window.webkit.messageHandlers.console.postMessage({level: level, args: Array.from(args)});
                } catch(e) { }
            };
            const wrap = function(orig, level){
                return function(){ send(level, arguments); try { return orig.apply(this, arguments); } catch(e){} };
            };
            if(window.console){
                console.log = wrap(console.log, 'log');
                console.info = wrap(console.info, 'info');
                console.warn = wrap(console.warn, 'warn');
                console.error = wrap(console.error, 'error');
            }
        })();
        """
        let consoleScript = WKUserScript(source: consoleJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(consoleScript)
        contentController.add(context.coordinator, name: "console")
        contentController.add(context.coordinator, name: "exit")

        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "HTMLContainer/1.0 (iPhone; iOS 15)"
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        // Allow read access to the whole Documents directory so assets and sibling folders load correctly
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        webView.loadFileURL(url, allowingReadAccessTo: docs)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onExit: () -> Void
        var onLoad: (() -> Void)?
        var onError: ((String) -> Void)?
        init(onExit: @escaping () -> Void, onLoad: (() -> Void)? = nil, onError: ((String) -> Void)? = nil) {
            self.onExit = onExit
            self.onLoad = onLoad
            self.onError = onError
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "exit" {
                DispatchQueue.main.async { self.onExit() }
                return
            }
            if message.name == "console" {
                // message.body expected to be a dict {level:..., args:[...]}
                var text = ""
                if let dict = message.body as? [String:Any] {
                    let level = dict["level"] as? String ?? "log"
                    if let args = dict["args"] as? [Any] {
                        let joined = args.map { "\($0)" }.joined(separator: " ")
                        text = "[console:\(level)] \(joined)"
                    } else {
                        text = "[console:\(level)] (no args)"
                    }
                } else {
                    text = "[console] \(message.body)"
                }
                appendToLog(text)
                return
            }
        }

        private func appendToLog(_ line: String) {
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let base = docs.appendingPathComponent("HTMLContainer")
            let logDir = base.appendingPathComponent("logs")
            if !fm.fileExists(atPath: logDir.path) {
                try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)
            }
            let logFile = logDir.appendingPathComponent("webview.log")
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let entry = "\(timestamp) \(line)\n"
            if let data = entry.data(using: .utf8) {
                if fm.fileExists(atPath: logFile.path) {
                    if let handle = try? FileHandle(forWritingTo: logFile) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: logFile)
                }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.onLoad?()
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.onError?(error.localizedDescription)
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.onError?(error.localizedDescription)
            }
        }
    }
}
