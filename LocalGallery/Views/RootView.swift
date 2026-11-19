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
    @Environment(PhotoLibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            TimelineScreen()
                .tabItem { Label("Library", systemImage: "photo.on.rectangle") }
                .tag(0)
            AlbumsScreen()
                .tabItem { Label("Albums", systemImage: "rectangle.stack") }
                .tag(1)
            SearchScreen()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(2)
        }
        // Hidden locks when the owner switches tabs or Gallery goes to the background. A brief
        // inactive moment (a system alert, the app switcher) only raises the privacy shield.
        .onChange(of: tab) { library.isHiddenUnlocked = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                library.isHiddenUnlocked = false
            }
        }
    }
}
