import SwiftUI

struct HTMLListView: View {
    var files: [URL]
    var onOpen: (URL) -> Void

    var body: some View {
        List {
            ForEach(files, id: \.self) { url in
                HStack {
                    Image(systemName: isFolder(url) ? "folder.fill" : "doc.text.fill")
                        .foregroundColor(.blue)
                    Text(url.lastPathComponent)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpen(url)
                }
                .contextMenu {
                    Button("Open") { onOpen(url) }
                    Button("Delete", role: .destructive) {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
        }
    }

    private func isFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }
}

struct HTMLListView_Previews: PreviewProvider {
    static var previews: some View {
        HTMLListView(files: []) { _ in }
    }
}
