import SwiftUI

@main
struct DocumentScannerApp: App {
    @State private var store = MetadataQueryLibraryStore()

    var body: some Scene {
        WindowGroup {
            LibraryView(store: store)
        }
    }
}
