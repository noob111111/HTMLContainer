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
        let urls = (try? fm.contentsOfDirectory(at: htmlsFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        htmlFiles = urls.filter { $0.pathExtension.lowercased() == "html" }
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
}
