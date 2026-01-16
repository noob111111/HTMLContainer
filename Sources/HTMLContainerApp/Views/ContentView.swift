import SwiftUI
import Foundation

struct ContentView: View {
    @StateObject private var fileHelper = FileHelper()
    @State private var selectedURL: URL?
    @State private var isPresenting = false
    @State private var showFolderPicker = false
    @State private var importError: String?
    @State private var showError = false
    @State private var isImporting = false
    @Binding var pendingURL: URL?

    var body: some View {
        ZStack {
            if isPresenting, let url = selectedURL {
                WebViewScreen(url: url, onExit: { isPresenting = false })
            } else {
                TabView {
                    NavigationView {
                        HTMLListView(files: fileHelper.htmlFiles, onOpen: { url in
                            print("Opening HTML: \(url.path)")
                            let logURL = url.deletingLastPathComponent().appendingPathComponent("html_opened.log")
                            let logContent = "Opened HTML: \(url.path)\nTimestamp: \(Date())"
                            try? logContent.write(to: logURL, atomically: true, encoding: .utf8)
                            selectedURL = url
                            isPresenting = true
                        }, onRefresh: {
                            fileHelper.refresh()
                        })
                        .navigationTitle("HTMLContainer")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                if isImporting {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Importing...")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.gray)
                                    .disabled(true)
                                } else {
                                    Button(action: { showFolderPicker = true }) {
                                        Image(systemName: "plus")
                                    }
                                }
                            }
                        }
                    }
                    .tabItem { Label("HTMLs", systemImage: "doc.text") }

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
                .onAppear {
                    let logURL = fileHelper.htmlsFolderURL.appendingPathComponent("app_started.log")
                    let logContent = "App started\nTimestamp: \(Date())"
                    try? logContent.write(to: logURL, atomically: true, encoding: .utf8)
                }
                .sheet(isPresented: $showFolderPicker) {
                    FolderPickerView { url in
                        isImporting = true
                        DispatchQueue.global(qos: .userInitiated).async {
                            do {
                                let _ = try fileHelper.importFolder(at: url)
                                DispatchQueue.main.async {
                                    isImporting = false
                                    showFolderPicker = false
                                    // Just import and close; don't auto-open
                                }
                            } catch {
                                DispatchQueue.main.async {
                                    importError = error.localizedDescription
                                    showError = true
                                    isImporting = false
                                }
                            }
                        }
                    }
                }
                .alert("Import Error", isPresented: $showError) {
                    Button("OK") { showError = false }
                } message: {
                    Text(importError ?? "Unknown error")
                }
                .onChange(of: pendingURL) { newURL in
                    if let url = newURL {
                        selectedURL = url
                        isPresenting = true
                        pendingURL = nil
                    }
                }
            }
        }
    }
}

struct WebViewScreen: View {
    let url: URL
    let onExit: () -> Void
    @AppStorage("closeButtonPosition") private var closeButtonPositionRaw: Int = CloseButtonPosition.topRight.rawValue

    var body: some View {
        let position = CloseButtonPosition(rawValue: closeButtonPositionRaw) ?? .topRight
        ZStack(alignment: position.alignment ?? .topTrailing) {
            HTMLWebView(url: url, onExit: onExit)
            if position != .disabled {
                Button(action: onExit) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                        .padding()
                }
            }
        }
    }
}

