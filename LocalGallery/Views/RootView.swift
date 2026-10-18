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
                TimelineScreen()
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
