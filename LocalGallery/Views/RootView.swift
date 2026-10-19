import SwiftUI

/// Chooses the screen for the current photo access state. Every state has a designed screen.
struct RootView: View {
    @Environment(PhotoLibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch library.access {
            case .notDetermined:
                AccessRationaleView()
            case .denied, .restricted:
                AccessDeniedView(restricted: library.access == .restricted)
            case .limited, .full:
                MainTabs()
            }
        }
        .onAppear {
            library.refreshAccess()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                library.refreshAccess()
            }
        }
    }
}

/// The three tabs, as in the Android app's bottom navigation.
struct MainTabs: View {
    var body: some View {
        TabView {
            TimelineScreen()
                .tabItem { Label("Library", systemImage: "photo.on.rectangle") }
            AlbumsScreen()
                .tabItem { Label("Albums", systemImage: "rectangle.stack") }
            SearchScreen()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
    }
}
