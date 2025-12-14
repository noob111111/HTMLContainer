import SwiftUI

struct HTMLListView: View {
    var files: [URL]
    var onOpen: (URL) -> Void

    private func htmlsBasePath() -> String {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base = docs.appendingPathComponent("HTMLContainer").appendingPathComponent("HTMLs").path
        return base
    }

    var body: some View {
        List {
            ForEach(files, id: \.self) { url in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.deletingPathExtension().lastPathComponent)
                            .font(.body)
                        Text(url.path.replacingOccurrences(of: htmlsBasePath(), with: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
