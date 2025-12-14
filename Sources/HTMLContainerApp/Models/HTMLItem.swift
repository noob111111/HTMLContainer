import Foundation

struct HTMLItem: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
}
