import SwiftUI

@main
struct GalleryApp: App {
    @State private var library = PhotoLibraryModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
    }
}
