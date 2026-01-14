import SwiftUI

struct ContentView: View {
    @StateObject private var fileHelper = FileHelper()
    @State private var selectedURL: URL?
    @State private var isPresenting = false
    @State private var showFolderPicker = false
    @State private var importError: String?
    @State private var showError = false

    var body: some View {
        NavigationView {
            HTMLListView(files: fileHelper.htmlFiles) { url in
                selectedURL = url
                isPresenting = true
            }
            .navigationTitle("HTMLContainer")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showFolderPicker = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView { url in
                do {
                    try fileHelper.importFolder(at: url)
                } catch {
                    importError = error.localizedDescription
                    showError = true
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

