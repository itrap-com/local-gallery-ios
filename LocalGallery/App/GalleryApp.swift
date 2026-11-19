import SwiftUI

@main
struct GalleryApp: App {
    @State private var library: PhotoLibraryModel
    private let shield: PrivacyShield

    init() {
        ShareExporter.removeLeftovers()
        let model = PhotoLibraryModel()
        _library = State(initialValue: model)
        shield = PrivacyShield { model.isHiddenUnlocked }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
    }
}
