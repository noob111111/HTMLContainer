import SwiftUI

struct ContentView: View {
    @StateObject private var fileHelper = FileHelper()
    @State private var selectedURL: URL?
    @State private var isPresenting = false
    @State private var showFolderPicker = false
    @State private var importError: String?
    @State private var showError = false
    @State private var isImporting = false

    var body: some View {
        NavigationView {
            HTMLListView(files: fileHelper.htmlFiles) { url in
                selectedURL = url
                isPresenting = true
            }
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
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView { url in
                isImporting = true
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try fileHelper.importFolder(at: url)
                        DispatchQueue.main.async {
                            isImporting = false
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
        .fullScreenCover(isPresented: $isPresenting) {
            if let url = selectedURL {
                HTMLWebView(url: url) {
                    isPresenting = false
                }
                .edgesIgnoringSafeArea(.all)
                .statusBar(hidden: true)
            }
        }
        .onAppear {
            fileHelper.prepareSampleIfNeeded()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

