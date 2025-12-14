import Foundation

enum Logger {
    static func logsDirectory() -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base = docs.appendingPathComponent("HTMLContainer")
        let logDir = base.appendingPathComponent("logs")
        if !fm.fileExists(atPath: logDir.path) {
            try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)
        }
        return logDir
    }

    static func append(_ message: String, to fileName: String = "app.log") {
        let fm = FileManager.default
        let logFile = logsDirectory().appendingPathComponent(fileName)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(timestamp) \(message)\n"
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
}
