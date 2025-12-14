import SwiftUI

struct HTMLListView: View {
    var files: [URL]
    var onOpen: (URL) -> Void

    var body: some View {
        List {
            ForEach(files, id: \.self) { url in
                HStack {
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
}

struct HTMLListView_Previews: PreviewProvider {
    static var previews: some View {
        HTMLListView(files: []) { _ in }
    }
}
