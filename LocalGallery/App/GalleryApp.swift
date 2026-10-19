import SwiftUI

@main
struct GalleryApp: App {
    @State private var library = PhotoLibraryModel()

    init() {
        ShareExporter.removeLeftovers()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
    }
}
