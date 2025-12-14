import SwiftUI

struct ContentView: View {
    @StateObject private var fileHelper = FileHelper()
    @State private var selectedURL: URL?
    @State private var isPresenting = false
    @State private var loadError: String?
    @State private var showingPicker = false
    @State private var showingError = false

    var body: some View {
        NavigationView {
            HTMLListView(files: fileHelper.htmlFiles) { url in
                selectedURL = url
                isPresenting = true
            }
            .navigationTitle("HTMLContainer")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingPicker = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isPresenting) {
            if let url = selectedURL {
                HTMLWebView(url: url) {
                    isPresenting = false
                } onLoad: {
                    // no-op for now
                } onError: { err in
                    loadError = err
                    showingError = true
                    isPresenting = false
                }
                .edgesIgnoringSafeArea(.all)
                .statusBar(hidden: true)
            }
        }
        .onAppear {
            fileHelper.prepareSampleIfNeeded()
        }
        .sheet(isPresented: $showingPicker) {
            FolderPicker { url in
                showingPicker = false
                guard let url = url else { return }
                do {
                    try fileHelper.importFolder(at: url)
                } catch {
                    loadError = "Import failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
        .alert("Load error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) { loadError = nil }
        }, message: {
            Text(loadError ?? "Unknown error")
        })
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
