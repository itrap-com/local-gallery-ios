import GalleryCore
import Photos
import SwiftUI

/// The grid used by every list of media: the timeline, albums, favorites and search results.
///
/// Tap opens the viewer. A long press, or Select, starts select mode, where taps toggle items and a
/// bottom bar shares, favorites or deletes the selection. Pinch changes the number of columns.
struct MediaGrid<Banner: View, Empty: View>: View {
    let feed: MediaFeed
    let title: String
    @ViewBuilder let banner: () -> Banner
    @ViewBuilder let empty: () -> Empty

    @Environment(PhotoLibraryModel.self) private var library
    @State private var viewer: ViewerStart?
    /// nil outside select mode. Holds identifiers, so it survives library changes.
    @State private var selection: Set<String>?
    @State private var actions = MediaActions()
    @State private var pinchHandled = false

    init(
        feed: MediaFeed,
        title: String,
        @ViewBuilder banner: @escaping () -> Banner,
        @ViewBuilder empty: @escaping () -> Empty
    ) {
        self.feed = feed
        self.title = title
        self.banner = banner
        self.empty = empty
    }

    var body: some View {
        content
            .navigationTitle(selection.map { "\($0.count) selected" } ?? title)
            .toolbar { toolbarContent }
            .toolbar(selection == nil ? .automatic : .hidden, for: .tabBar)
            .fullScreenCover(item: $viewer) { start in
                ViewerScreen(feed: feed, startIndex: start.index)
                    .environment(library)
            }
            .mediaActions(actions)
            .onAppear { feed.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if !feed.isLoaded {
            ProgressView("Loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let assets = feed.assets, assets.count > 0 {
            grid(assets)
        } else {
            VStack(spacing: 0) {
                banner()
                empty()
            }
        }
    }

    private func grid(_ assets: PHFetchResult<PHAsset>) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: library.gridColumns)
        return ScrollView {
            banner()
            LazyVGrid(columns: columns, spacing: 2, pinnedViews: feed.showsMonths ? [.sectionHeaders] : []) {
                ForEach(feed.sections) { section in
                    Section {
                        ForEach(section.range, id: \.self) { index in
                            if index < assets.count {
                                tile(assets.object(at: index), index: index)
                            }
                        }
                    } header: {
                        if feed.showsMonths {
                            SectionHeader(title: Self.title(for: section.month))
                        }
                    }
                }
            }
        }
        .simultaneousGesture(pinch)
    }

    private func tile(_ asset: PHAsset, index: Int) -> some View {
        let id = asset.localIdentifier
        return AssetTile(
            asset: asset,
            imageManager: library.imageManager,
            isFavorite: library.favorites.list.contains(id),
            isSelected: selection.map { $0.contains(id) }
        )
        .contentShape(Rectangle())
        .onTapGesture { tap(id: id, index: index) }
        .onLongPressGesture(minimumDuration: 0.35) { startSelecting(with: id) }
        .accessibilityAddTraits(selection == nil ? .isButton : [.isButton, .isToggle])
        .accessibilityAction { tap(id: id, index: index) }
        .accessibilityAction(named: selection == nil ? "Select" : "Open") {
            if selection == nil {
                startSelecting(with: id)
            } else {
                viewer = ViewerStart(index: index)
            }
        }
    }

    // MARK: Selection

    private func tap(id: String, index: Int) {
        guard var current = selection else {
            viewer = ViewerStart(index: index)
            return
        }
        if current.contains(id) {
            current.remove(id)
        } else {
            current.insert(id)
        }
        selection = current
    }

    private func startSelecting(with id: String) {
        if selection == nil {
            selection = [id]
        }
    }

    private func selectedAssets() -> [PHAsset] {
        guard let selection, !selection.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(selection), options: MediaFetch.options())
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    private func selectAll() {
        guard let assets = feed.assets else { return }
        var ids = Set<String>()
        assets.enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        selection = ids
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let selection {
            ToolbarItem(placement: .topBarLeading) {
                Button("Select All", action: selectAll)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { self.selection = nil }
                    .fontWeight(.semibold)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                ShareMenu(assets: selectedAssets, actions: actions) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button {
                    library.favorites.toggle(selectedAssets())
                } label: {
                    Image(systemName: allSelectedAreFavorites ? "heart.slash" : "heart")
                }
                .accessibilityLabel(allSelectedAreFavorites ? "Remove from favorites" : "Add to favorites")
                .disabled(selection.isEmpty)
                Spacer()
                Button(role: .destructive) {
                    let assets = selectedAssets()
                    Task {
                        if await actions.delete(assets, library: library) {
                            self.selection = nil
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete")
                .disabled(selection.isEmpty)
            }
        } else if feed.assets.map({ $0.count > 0 }) == true {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select") { self.selection = [] }
            }
        }
    }

    private var allSelectedAreFavorites: Bool {
        guard let selection, !selection.isEmpty else { return false }
        return selection.allSatisfy(library.favorites.list.contains)
    }

    // MARK: Pinch

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard !pinchHandled else { return }
                if value.magnification > 1.25 {
                    library.gridColumns = max(2, library.gridColumns - 1)
                    pinchHandled = true
                } else if value.magnification < 0.8 {
                    library.gridColumns = min(7, library.gridColumns + 1)
                    pinchHandled = true
                }
            }
            .onEnded { _ in pinchHandled = false }
    }

    static func title(for month: MonthKey?) -> String {
        guard let month,
              let date = Calendar.current.date(from: DateComponents(year: month.year, month: month.month))
        else {
            return "Unknown date"
        }
        return date.formatted(.dateTime.month(.wide).year())
    }
}

extension MediaGrid where Banner == EmptyView {
    init(feed: MediaFeed, title: String, @ViewBuilder empty: @escaping () -> Empty) {
        self.init(feed: feed, title: title, banner: { EmptyView() }, empty: empty)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .accessibilityAddTraits(.isHeader)
    }
}
