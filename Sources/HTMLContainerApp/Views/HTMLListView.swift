import SwiftUI

struct HTMLListView: View {
    var files: [URL]
    var onOpen: (URL) -> Void
    @State private var selectedFolder: URL?
    @State private var showFilePicker = false

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
                    if isFolder(url) {
                        selectedFolder = url
                        showFilePicker = true
                    } else {
                        onOpen(url)
                    }
                }
                .contextMenu {
                    Button("Open") {
                        if isFolder(url) {
                            selectedFolder = url
                            showFilePicker = true
                        } else {
                            onOpen(url)
                        }
                    }
                    Button("Delete", role: .destructive) {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
        }
        .sheet(isPresented: $showFilePicker) {
            if let folder = selectedFolder {
                FilePickerSheet(folder: folder, onSelect: { file in
                    onOpen(file)
                    showFilePicker = false
                })
                .modifier(SheetModifier())
            }
        }
    }

    private func isFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }
}

// Sheet to pick an HTML file from a folder
struct FilePickerSheet: View {
    let folder: URL
    var onSelect: (URL) -> Void
    @State private var htmlFiles: [URL] = []
    @State private var selectedFile: URL?

    var body: some View {
        NavigationView {
            VStack {
                if htmlFiles.isEmpty {
                    Text("No HTML files found in this folder")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List {
                        ForEach(htmlFiles, id: \.self) { file in
                            Button(action: {
                                SettingsStore.setPreferredFile(file.lastPathComponent, forFolder: folder.path)
                                onSelect(file)
                            }) {
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading) {
                                        Text(file.lastPathComponent)
                                            .foregroundColor(.primary)
                                        if selectedFile == file {
                                            Text("(Previously selected)")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                    }
                                    Spacer()
                                    if selectedFile == file {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose HTML File")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            loadHTMLFiles()
        }
    }

    private func loadHTMLFiles() {
        let fm = FileManager.default
        let all = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        htmlFiles = all.filter { $0.pathExtension.lowercased() == "html" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        // Restore previously selected file if it exists
        if let savedName = SettingsStore.preferredFile(forFolder: folder.path) {
            selectedFile = htmlFiles.first { $0.lastPathComponent == savedName }
        }
    }
}

struct HTMLListView_Previews: PreviewProvider {
    static var previews: some View {
        HTMLListView(files: []) { _ in }
    }
}

// Modifier for iOS 16+ sheet presentation features
struct SheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}
