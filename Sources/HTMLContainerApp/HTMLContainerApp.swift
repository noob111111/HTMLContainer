import SwiftUI

@main
struct HTMLContainerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onOpenURL { url in
            // Handle custom URL scheme if needed
            print("Opened with URL: \(url)")
        }
    }
}
