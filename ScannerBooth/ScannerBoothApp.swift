import SwiftUI

@main
struct ScannerBoothApp: App {
    @StateObject private var library = PhotoBoothLibraryStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowToolbarStyle(.unified)
    }
}
