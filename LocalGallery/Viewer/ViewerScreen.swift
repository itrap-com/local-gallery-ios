import Photos
import SwiftUI

/// Identifies which timeline item the viewer opens on.
struct ViewerStart: Identifiable {
    let index: Int
    var id: Int { index }
}

/// The full-screen viewer: swipe sideways between items, pinch or double-tap to zoom, swipe down
/// or tap Close to return. Tapping a photo hides or shows the controls.
///
/// It reads the same feed as the grid it was opened from. When the library changes while it is open, it
/// stays on the same item; if that item is gone it shows its neighbour, and it closes when nothing
/// visible is left.
struct ViewerScreen: View {
    @Environment(PhotoLibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    let feed: MediaFeed

    @State private var position: Int?
    @State private var currentAsset: PHAsset?
    @State private var showsChrome = true
    @State private var isZoomed = false
    @State private var dismissProgress = 0.0
    @State private var showsDetails = false
    @State private var actions = MediaActions()
    private let startIndex: Int

    init(feed: MediaFeed, startIndex: Int) {
        self.feed = feed
        self.startIndex = startIndex
        _position = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let assets = feed.assets, assets.count > 0 {
                pager(assets)
            }
            chrome
                .opacity(showsChrome ? 1 - dismissProgress : 0)
                .allowsHitTesting(showsChrome)
                .animation(.easeOut(duration: 0.2), value: showsChrome)
        }
        .statusBarHidden(!showsChrome)
        .persistentSystemOverlays(showsChrome ? .automatic : .hidden)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsDetails) {
            if let currentAsset {
                DetailsSheet(asset: currentAsset)
                    .presentationDetents([.medium, .large])
            }
        }
        .mediaActions(actions)
        .onAppear { follow(feed.assets) }
        .onChange(of: feed.assets) { _, assets in follow(assets) }
        .onChange(of: position) { _, index in
            isZoomed = false
            if let index, let assets = feed.assets, index < assets.count {
                let asset = assets.object(at: index)
                currentAsset = asset
                // A video page leaves taps to the player's own controls, so Close must stay visible.
                if asset.mediaType == .video {
                    showsChrome = true
                }
            }
        }
    }

    private func pager(_ assets: PHFetchResult<PHAsset>) -> some View {
        ScrollViewReader { proxy in
            pagerScroll(assets)
                // The initial scroll position isn't always honoured on first layout, so open on the
                // tapped item explicitly.
                .onAppear { proxy.scrollTo(position ?? startIndex) }
        }
    }

    private func pagerScroll(_ assets: PHFetchResult<PHAsset>) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0..<assets.count, id: \.self) { index in
                    page(assets.object(at: index), index: index)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $position)
        .scrollIndicators(.hidden)
        .scrollDisabled(isZoomed)
        .ignoresSafeArea()
        .accessibilityAction(named: "Next item") { step(1, count: assets.count) }
        .accessibilityAction(named: "Previous item") { step(-1, count: assets.count) }
    }

    @ViewBuilder
    private func page(_ asset: PHAsset, index: Int) -> some View {
        let isCurrent = index == position
        if asset.mediaType == .video {
            VideoPage(
                asset: asset,
                imageManager: library.imageManager,
                isCurrent: isCurrent,
                showsChrome: showsChrome
            )
        } else {
            PhotoPage(
                asset: asset,
                imageManager: library.imageManager,
                isCurrent: isCurrent,
                showsChrome: showsChrome,
                onTap: { showsChrome.toggle() },
                onZoomChange: { zoomed in
                    if isCurrent {
                        isZoomed = zoomed
                    }
                },
                onDismissProgress: { dismissProgress = $0 },
                onDismiss: { dismiss() }
            )
        }
    }

    private var chrome: some View {
        VStack {
            HStack(alignment: .center) {
                ChromeButton(symbol: "xmark", label: "Close") { dismiss() }
                Spacer(minLength: 12)
                if let date = currentAsset?.creationDate {
                    VStack(spacing: 2) {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.semibold))
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white)
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 12)
                // Balances the close button so the date stays centred.
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
            if let currentAsset {
                bottomBar(currentAsset)
            }
        }
    }

    private func bottomBar(_ asset: PHAsset) -> some View {
        let isFavorite = library.favorites.contains(asset)
        return HStack {
            ShareMenu(assets: { [asset] }, actions: actions) {
                ChromeIcon(symbol: "square.and.arrow.up")
            }
            Spacer()
            ChromeButton(
                symbol: isFavorite ? "heart.fill" : "heart",
                label: isFavorite ? "Remove from favorites" : "Add to favorites"
            ) {
                library.favorites.toggle([asset])
            }
            Spacer()
            ChromeButton(symbol: "info.circle", label: "Details") { showsDetails = true }
            Spacer()
            ChromeButton(symbol: "trash", label: "Delete") {
                Task { _ = await actions.delete([asset], library: library) }
            }
        }
        .padding(.horizontal, 24)
        // On a video, sit above the system player's own controls.
        .padding(.bottom, asset.mediaType == .video ? 96 : 8)
    }

    private func step(_ delta: Int, count: Int) {
        guard let position else { return }
        let next = position + delta
        if (0..<count).contains(next) {
            self.position = next
        }
    }

    /// Keeps the viewer on the same item across library changes.
    private func follow(_ assets: PHFetchResult<PHAsset>?) {
        guard let assets, assets.count > 0 else {
            dismiss()
            return
        }
        if let currentAsset {
            let index = assets.index(of: currentAsset)
            if index != NSNotFound {
                position = index
                return
            }
        }
        let index = min(max(position ?? 0, 0), assets.count - 1)
        position = index
        currentAsset = assets.object(at: index)
    }
}

/// A round control that stays legible over any photo.
private struct ChromeButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChromeIcon(symbol: symbol)
        }
        .accessibilityLabel(label)
    }
}

private struct ChromeIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
    }
}
