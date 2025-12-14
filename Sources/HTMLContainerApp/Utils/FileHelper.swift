import Foundation

final class FileHelper: ObservableObject {
    @Published var htmlFiles: [URL] = []
    private let baseFolderName = "HTMLContainer"
    private let htmlsFolderName = "HTMLs"

    init() {
        refresh()
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
        let fm = FileManager.default
        var found: [URL] = []
        if let enumerator = fm.enumerator(at: htmlsFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "html" {
                    found.append(fileURL)
                }
            }
        }
        htmlFiles = found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func prepareSampleIfNeeded() {
        let fm = FileManager.default
        let sampleDir = htmlsFolderURL.appendingPathComponent("Sample")
        if !fm.fileExists(atPath: sampleDir.path) {
            try? fm.createDirectory(at: sampleDir, withIntermediateDirectories: true)
            if let bundleSample = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "HTMLs/Sample") {
                let dest = sampleDir.appendingPathComponent("index.html")
                try? fm.copyItem(at: bundleSample, to: dest)
            }
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
