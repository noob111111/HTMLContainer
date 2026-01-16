import SwiftUI

@main
struct HTMLContainerApp: App {
    @State private var pendingURL: URL?
    
    var body: some Scene {
        WindowGroup {
            ContentView(pendingURL: $pendingURL)
        }
        .onOpenURL { url in
            // Handle custom URL scheme
            print("Opened with URL: \(url)")
            if url.scheme == "htmlcontainer" {
                // Extract path from URL (e.g., htmlcontainer://folder/file.html)
                if let path = url.host?.removingPercentEncoding {
                    let htmlPath = path.hasSuffix(".html") ? path : (path + "/index.html")
                    // Find the HTML file in our documents
                    let fm = FileManager.default
                    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let htmlsDir = docs.appendingPathComponent("HTMLContainer").appendingPathComponent("HTMLs")
                    let targetURL = htmlsDir.appendingPathComponent(htmlPath)
                    
                    if fm.fileExists(atPath: targetURL.path) {
                        pendingURL = targetURL
                        print("Found HTML file: \(targetURL.path)")
                    } else {
                        print("HTML file not found: \(targetURL.path)")
                    }
                }
            }
        }
    }
}
