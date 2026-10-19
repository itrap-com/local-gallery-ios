import Photos
import SwiftUI

/// The Albums tab: Favorites and the system collections first, then the owner's albums.
struct AlbumsScreen: View {
    @Environment(PhotoLibraryModel.self) private var library
    @State private var model = AlbumsModel()

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoaded {
                    ScrollView {
                        if library.access == .limited {
                            LimitedAccessBanner()
                        }
                        albumSection(nil, model.system)
                        if !model.user.isEmpty {
                            albumSection("My Albums", model.user)
                        }
                    }
                } else {
                    ProgressView("Loading albums")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Albums")
            .navigationDestination(for: AlbumRoute.self) { route in
                AlbumScreen(route: route)
            }
        }
        .onAppear { model.reload(favoriteIDs: library.favorites.list.ids) }
        .onChange(of: library.favorites.list) { _, list in model.reload(favoriteIDs: list.ids) }
        .onChange(of: library.accessGeneration) { model.reload(favoriteIDs: nil) }
    }

    private func albumSection(_ title: String?, _ albums: [AlbumSummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 16)
                    .accessibilityAddTraits(.isHeader)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(albums) { album in
                    NavigationLink(value: AlbumRoute(album)) {
                        AlbumCard(album: album, imageManager: library.imageManager)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }
}

/// A navigation value for one album. Hashable by identity, so it is cheap to push.
struct AlbumRoute: Hashable {
    let id: String
    let title: String
    let source: AlbumSummary.Source

    init(_ album: AlbumSummary) {
        id = album.id
        title = album.title
        source = album.source
    }

    static func == (lhs: AlbumRoute, rhs: AlbumRoute) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct AlbumCard: View {
    let album: AlbumSummary
    let imageManager: PHCachingImageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let cover = album.cover {
                    AssetTile(asset: cover, imageManager: imageManager)
                } else {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.secondary.opacity(0.12))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Image(systemName: album.symbol)
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
            Label(album.title, systemImage: album.symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(album.count.formatted())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(album.title), \(album.count) items")
        .accessibilityAddTraits(.isButton)
    }
}

/// One album, Favorites included, as a grid.
struct AlbumScreen: View {
    @Environment(PhotoLibraryModel.self) private var library
    let route: AlbumRoute
    @State private var feed: MediaFeed

    init(route: AlbumRoute) {
        self.route = route
        _feed = State(initialValue: MediaFeed(showsMonths: true, fetch: Self.fetch(for: route.source, favorites: [])))
    }

    var body: some View {
        MediaGrid(feed: feed, title: route.title) {
            MessageScreen(
                symbol: "rectangle.stack",
                title: isFavorites ? "No favorites yet" : "Nothing visible here",
                message: isFavorites
                    ? "Tap the heart on any photo or video to add it. Favorites are stored only in Gallery on this iPhone."
                    : "This album has no photos or videos Gallery can see."
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if isFavorites {
                feed.update(Self.fetch(for: route.source, favorites: library.favorites.list.ids))
            }
        }
        .onChange(of: library.favorites.list) { _, list in
            if isFavorites {
                feed.update(Self.fetch(for: route.source, favorites: list.ids))
            }
        }
        .onChange(of: library.accessGeneration) { feed.reload() }
    }

    private var isFavorites: Bool {
        if case .favorites = route.source { return true }
        return false
    }

    private static func fetch(for source: AlbumSummary.Source, favorites: [String]) -> MediaFeed.Fetch {
        switch source {
        case .favorites:
            return { MediaFetch.identifiers(favorites) }
        case .collection(let collection):
            return { MediaFetch.collection(collection) }
        }
    }
}
