import Foundation

final class FileHelper: ObservableObject {
    @Published var htmlFiles: [URL] = []
    private let baseFolderName = "HTMLContainer"
    private let htmlsFolderName = "HTMLs"

    init() {
        // perform setup off the main thread to avoid blocking app launch
        DispatchQueue.global(qos: .userInitiated).async {
            self.prepareSampleIfNeeded()
        }
    }

    var htmlsFolderURL: URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent(baseFolderName).appendingPathComponent(htmlsFolderName)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var found: [URL] = []
            if let enumerator = fm.enumerator(at: self.htmlsFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension.lowercased() == "html" {
                        found.append(fileURL)
                    }
                }
            }
            let sorted = found.sorted { $0.lastPathComponent < $1.lastPathComponent }
            DispatchQueue.main.async {
                self.htmlFiles = sorted
            }
        }
    }

    func prepareSampleIfNeeded() {
        let fm = FileManager.default
        let sampleDir = htmlsFolderURL.appendingPathComponent("Sample")
        var created = false
        if !fm.fileExists(atPath: sampleDir.path) {
            try? fm.createDirectory(at: sampleDir, withIntermediateDirectories: true)
            created = true
        }

        // Copy bundled sample files (index.html and style.css) into Sample folder
        if created {
            if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "HTMLs/Sample") {
                let dest = sampleDir.appendingPathComponent("index.html")
                try? fm.copyItem(at: indexURL, to: dest)
            }
            if let cssURL = Bundle.main.url(forResource: "style", withExtension: "css", subdirectory: "HTMLs/Sample") {
                let dest2 = sampleDir.appendingPathComponent("style.css")
                try? fm.copyItem(at: cssURL, to: dest2)
            }
            // create an initial webview.log and app.log entry
            Logger.append("Prepared bundled Sample")
            Logger.append("Prepared bundled Sample", to: "webview.log")
        }

        refresh()
    }

    func importFolder(at url: URL) throws {
        let fm = FileManager.default
        let destFolder = htmlsFolderURL.appendingPathComponent(url.lastPathComponent)
        var target = destFolder
        // avoid clobbering existing folder; if exists, append a number
        var i = 1
        while fm.fileExists(atPath: target.path) {
            target = htmlsFolderURL.appendingPathComponent("\(url.lastPathComponent)-\(i)")
            i += 1
        }

        let useSecurity = url.startAccessingSecurityScopedResource()
        defer { if useSecurity { url.stopAccessingSecurityScopedResource() } }

        try fm.copyItem(at: url, to: target)
        refresh()
    }
}
