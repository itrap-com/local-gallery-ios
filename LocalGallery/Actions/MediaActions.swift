import Photos
import SwiftUI
import UIKit

/// The actions every screen offers on one item or a selection: share, favorite and delete.
///
/// It owns the in-progress state and the messages, so the grid and the viewer behave the same way.
@MainActor
@Observable
final class MediaActions {
    var shareBatch: ShareBatch?
    var isPreparing = false
    var notice: String?

    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var exportGeneration = 0
    /// A note to show once the share sheet closes; an alert can't open while the sheet is up.
    @ObservationIgnored private var pendingNotice: String?
    @ObservationIgnored private var presentedBatch: ShareBatch?

    func share(_ assets: [PHAsset], removeLocation: Bool) {
        guard !assets.isEmpty, !isPreparing else { return }
        isPreparing = true
        exportGeneration += 1
        let token = exportGeneration
        exportTask = Task {
            let batch = await ShareExporter.export(assets, removeLocation: removeLocation)
            // A cancelled or superseded export cleans up after itself and changes nothing else.
            guard token == exportGeneration, !Task.isCancelled else {
                batch?.discard()
                return
            }
            isPreparing = false
            guard let batch else {
                notice = "Gallery couldn't prepare these items for sharing."
                return
            }
            if batch.files.isEmpty {
                notice = Self.skippedText(batch.skipped, total: assets.count)
                return
            }
            pendingNotice = batch.skipped > 0 ? Self.skippedText(batch.skipped, total: assets.count) : nil
            presentedBatch = batch
            shareBatch = batch
        }
    }

    func cancelPreparing() {
        exportGeneration += 1
        exportTask?.cancel()
        exportTask = nil
        isPreparing = false
    }

    /// Called when the share sheet closes, however it was closed.
    func shareSheetDismissed() {
        presentedBatch?.discard()
        presentedBatch = nil
        if let pendingNotice {
            notice = pendingNotice
            self.pendingNotice = nil
        }
    }

    /// Returns true when the items were deleted.
    func delete(_ assets: [PHAsset], library: PhotoLibraryModel) async -> Bool {
        do {
            return try await library.delete(assets)
        } catch {
            notice = "Gallery couldn't delete \(assets.count == 1 ? "this item" : "these items"). iOS may not allow deleting them."
            return false
        }
    }

    private static func skippedText(_ skipped: Int, total: Int) -> String {
        if skipped == total {
            return total == 1
                ? "This item couldn't be shared. Its original may be only in iCloud, and Gallery doesn't download it."
                : "These items couldn't be shared. Their originals may be only in iCloud, and Gallery doesn't download them."
        }
        return "\(skipped) of \(total) items couldn't be shared and were left out. Their originals may be only in iCloud."
    }
}

/// Attaches the share sheet, the preparing overlay and the notice alert for a `MediaActions`.
struct MediaActionPresenter: ViewModifier {
    @Bindable var actions: MediaActions

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.shareBatch, onDismiss: { actions.shareSheetDismissed() }) { batch in
                ActivitySheet(batch: batch) {
                    actions.shareBatch = nil
                }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
            }
            .overlay {
                if actions.isPreparing {
                    PreparingOverlay { actions.cancelPreparing() }
                }
            }
            .alert(
                "Gallery",
                isPresented: Binding(get: { actions.notice != nil }, set: { if !$0 { actions.notice = nil } }),
                presenting: actions.notice
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { text in
                Text(text)
            }
    }
}

extension View {
    func mediaActions(_ actions: MediaActions) -> some View {
        modifier(MediaActionPresenter(actions: actions))
    }
}

/// The system share sheet over prepared files. The files are removed when it closes.
struct ActivitySheet: UIViewControllerRepresentable {
    let batch: ShareBatch
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: batch.files, applicationActivities: nil)
        let folder = batch.folder
        controller.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: folder)
            onFinish()
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: UIActivityViewController, coordinator: ()) {
        controller.completionWithItemsHandler = nil
    }
}

private struct PreparingOverlay: View {
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                Text("Preparing to share")
                    .font(.callout)
                Button("Cancel", role: .cancel, action: onCancel)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// The share control: a menu whose first choice removes location, as the Android app's privacy
/// export does.
struct ShareMenu<Label: View>: View {
    let assets: () -> [PHAsset]
    let actions: MediaActions
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            Button {
                actions.share(assets(), removeLocation: true)
            } label: {
                SwiftUI.Label("Share without location", systemImage: "location.slash")
            }
            Button {
                actions.share(assets(), removeLocation: false)
            } label: {
                SwiftUI.Label("Share original", systemImage: "square.and.arrow.up")
            }
        } label: {
            label()
        }
        .accessibilityLabel("Share")
    }
}
