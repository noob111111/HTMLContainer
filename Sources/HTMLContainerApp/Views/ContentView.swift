import SwiftUI

struct ContentView: View {
    @StateObject private var fileHelper = FileHelper()
    @State private var selectedURL: URL?
    @State private var isPresenting = false

    var body: some View {
        NavigationView {
            HTMLListView(files: fileHelper.htmlFiles) { url in
                selectedURL = url
                isPresenting = true
            }
            .navigationTitle("HTMLContainer")
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
