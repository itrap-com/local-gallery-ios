import SwiftUI
import UIKit

/// Shown before the system prompt, so the request is explained first.
struct AccessRationaleView: View {
    @Environment(PhotoLibraryModel.self) private var library

    var body: some View {
        MessageScreen(
            symbol: "photo.on.rectangle",
            title: "Your photos, on this iPhone",
            message: "Gallery needs photo access to show your library. You can allow all photos or only the ones you choose. Gallery works offline and never uploads anything.",
            actionTitle: "Continue",
            action: requestAccess
        )
    }

    private func requestAccess() {
        Task {
            await library.requestAccess()
        }
    }
}

/// Shown when access is denied or restricted. It never claims the library is empty.
struct AccessDeniedView: View {
    let restricted: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        if restricted {
            MessageScreen(
                symbol: "eye.slash",
                title: "No visible photos or videos",
                message: "Photo access is restricted on this iPhone, so Gallery can't show your library."
            )
        } else {
            MessageScreen(
                symbol: "eye.slash",
                title: "No visible photos or videos",
                message: "Gallery can only show what iOS allows it to see. To show your library, allow photo access in Settings.",
                actionTitle: "Open Settings",
                action: openSettings
            )
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

/// A quiet note above the grid while access is limited. It never nags with system alerts.
struct LimitedAccessBanner: View {
    @Environment(PhotoLibraryModel.self) private var library

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Gallery can only show the photos you selected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Manage") {
                library.presentLimitedLibraryPicker()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// The fetch returned nothing. It never claims the user has no photos.
struct EmptyLibraryView: View {
    let limited: Bool
    @Environment(PhotoLibraryModel.self) private var library

    var body: some View {
        if limited {
            MessageScreen(
                symbol: "photo.on.rectangle",
                title: "No visible photos or videos",
                message: "Gallery can only show the photos you selected, and none are selected right now.",
                actionTitle: "Choose photos",
                action: { library.presentLimitedLibraryPicker() }
            )
        } else {
            MessageScreen(
                symbol: "photo.on.rectangle",
                title: "No visible photos or videos",
                message: "This can happen if photo access is limited or this iPhone has no photos yet."
            )
        }
    }
}
