import SwiftUI
import UIKit

struct HTMLListView: View {
    var files: [URL]
    var onOpen: (URL) -> Void
    var onRefresh: () -> Void
    @State private var selectedFolder: URL?
    @State private var showNoHTMLAlert = false

    var body: some View {
        ZStack {
            if let folder = selectedFolder {
                FilePickerSheet(folder: folder, onSelect: { file in
                    selectedFolder = nil
                    onOpen(file)
                })
            } else {
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
                                handleFolderTap(url)
                            } else {
                                onOpen(url)
                            }
                        }
                        .contextMenu {
                            Button("Open") {
                                if isFolder(url) {
                                    handleFolderTap(url)
                                } else {
                                    onOpen(url)
                                }
                            }
                            Button("Open in Folder") {
                                let folderURL = isFolder(url) ? url : url.deletingLastPathComponent()
                                UIApplication.shared.open(folderURL)
                            }
                            Button("Delete", role: .destructive) {
                                try? FileManager.default.removeItem(at: url)
                                onRefresh()
                            }
                        }
                    }
                }
                .alert("No HTML Files Found", isPresented: $showNoHTMLAlert) {
                    Button("OK") { showNoHTMLAlert = false }
                } message: {
                    Text("This folder doesn't contain any HTML files.")
                }
            }
        }
    }

    private func isFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    private func handleFolderTap(_ folderURL: URL) {
        let logURL = folderURL.appendingPathComponent("folder_tapped.log")
        let logContent = "Folder tapped: \(folderURL.path)\nTimestamp: \(Date())"
        try? logContent.write(to: logURL, atomically: true, encoding: .utf8)
        
        let fm = FileManager.default
        let all = (try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let htmlFiles = all.filter { $0.pathExtension.lowercased() == "html" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        // Check if index.html exists
        let indexURL = folderURL.appendingPathComponent("index.html")
        let hasIndex = fm.fileExists(atPath: indexURL.path)

        // Get current setting (assuming we add it to Settings)
        let setting = AutoOpenSetting(rawValue: UserDefaults.standard.integer(forKey: "htmlSelectionSetting")) ?? .auto

        switch setting {
        case .auto:
            if hasIndex {
                onOpen(indexURL)
            } else if !htmlFiles.isEmpty {
                // Auto-pick first HTML file
                onOpen(htmlFiles[0])
            } else {
                // No HTML files, show alert
                showNoHTMLAlert = true
            }
        case .askFirstTime:
            let key = folderURL.path
            if SettingsStore.hasAsked(forFolderPath: key) {
                if hasIndex {
                    onOpen(indexURL)
                } else if !htmlFiles.isEmpty {
                    onOpen(htmlFiles[0])
                } else {
                    showNoHTMLAlert = true
                }
            } else {
                SettingsStore.markAsked(forFolderPath: key)
                if !htmlFiles.isEmpty {
                    selectedFolder = folderURL
                } else {
                    showNoHTMLAlert = true
                }
            }
        case .alwaysAsk:
            if !htmlFiles.isEmpty {
                selectedFolder = folderURL
            } else {
                showNoHTMLAlert = true
            }
        }
    }
}

// Sheet to pick an HTML file from a folder
struct FilePickerSheet: View {
    let folder: URL
    var onSelect: (URL) -> Void
    @State private var htmlFiles: [URL] = []
    @State private var selectedFile: URL?
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        mainContent
        .onAppear {
            let fm = FileManager.default
            let all = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            htmlFiles = all.filter { $0.pathExtension.lowercased() == "html" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            print("FilePickerSheet loaded \(htmlFiles.count) HTML files from \(folder.path)")
            
            let logURL = folder.appendingPathComponent("sheet_opened.log")
            let logContent = "Sheet opened for: \(folder.path)\nHTML files: \(htmlFiles.map { $0.lastPathComponent })\nTimestamp: \(Date())"
            try? logContent.write(to: logURL, atomically: true, encoding: .utf8)
            
            // Restore previously selected file if it exists
            if let savedName = SettingsStore.preferredFile(forFolder: folder.path) {
                selectedFile = htmlFiles.first { $0.lastPathComponent == savedName }
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 20) {
            Text("Choose HTML File")
                .font(.title2)
                .bold()
            if htmlFiles.isEmpty {
                Text("No HTML files found in this folder")
                    .foregroundColor(.gray)
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .padding(.top)
            } else {
                List(htmlFiles, id: \.self) { file in
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
                .listStyle(.plain)
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .padding(.top)
            }
        }
        .padding()
    }
}

struct HTMLListView_Previews: PreviewProvider {
    static var previews: some View {
        HTMLListView(files: [], onOpen: { _ in }, onRefresh: {})
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
