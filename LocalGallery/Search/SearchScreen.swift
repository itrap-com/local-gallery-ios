import GalleryCore
import Photos
import SwiftUI

/// The Search tab. Everything runs on this iPhone: the text is parsed locally, never logged and
/// never sent anywhere.
///
/// It understands kinds ("videos", "selfies", "live", "screenshots", "favorites"), dates ("2024",
/// "october", "oct 2023") and album names.
struct SearchScreen: View {
    @Environment(PhotoLibraryModel.self) private var library
    @State private var text = ""
    @State private var feed = MediaFeed(showsMonths: true) { MediaFetch.identifiers([]) }
    @State private var query = SearchQuery()

    private static let suggestions: [(String, String)] = [
        ("Videos", "video"), ("Selfies", "person.crop.square"), ("Screenshots", "camera.viewfinder"),
        ("Live Photos", "livephoto"), ("Favorites", "heart"), ("Panoramas", "pano"),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    suggestionList
                } else {
                    MediaGrid(feed: feed, title: "Search") {
                        MessageScreen(
                            symbol: "magnifyingglass",
                            title: "No matches",
                            message: "Nothing visible matches. Other words are matched against album names; search also understands videos, selfies, favorites, a year or a month."
                        )
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Videos, 2024, an album…")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .task(id: text) {
            // A short pause, so the library isn't fetched on every keystroke.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            run(SearchQuery.parse(text))
        }
        .onChange(of: library.favorites.list) {
            if query.kinds.contains(.favorite) {
                run(query)
            }
        }
        .onChange(of: library.accessGeneration) { run(query) }
    }

    private var suggestionList: some View {
        List {
            Section("Try") {
                ForEach(Self.suggestions, id: \.0) { title, symbol in
                    Button {
                        text = title.lowercased()
                    } label: {
                        Label(title, systemImage: symbol)
                    }
                }
            }
            Section {
                Text("Search runs only on this iPhone. Gallery doesn't keep or send what you type.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func run(_ next: SearchQuery) {
        query = next
        guard !next.isEmpty else { return }
        let favorites = library.favorites.list.ids
        let calendar = Calendar.current
        feed.update {
            Self.fetch(next, favorites: favorites, calendar: calendar)
        }
    }

    /// Builds one fetch from the parsed query. Runs off the main thread.
    ///
    /// Screenshots, Live Photos, panoramas and selfies come from the system's own smart albums,
    /// so no item is classified by Gallery itself.
    nonisolated private static func fetch(
        _ query: SearchQuery,
        favorites: [String],
        calendar: Calendar
    ) -> PHFetchResult<PHAsset> {
        var predicates: [NSPredicate] = []

        var types: [NSPredicate] = []
        if query.kinds.contains(.photo) {
            types.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
        }
        if query.kinds.contains(.video) {
            types.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))
        }
        let smart: [(SearchKind, PHAssetCollectionSubtype)] = [
            (.screenshot, .smartAlbumScreenshots), (.live, .smartAlbumLivePhotos),
            (.panorama, .smartAlbumPanoramas), (.selfie, .smartAlbumSelfPortraits),
        ]
        let wanted = smart.filter { query.kinds.contains($0.0) }
        if !wanted.isEmpty {
            var ids: [String] = []
            for (_, subtype) in wanted {
                if let album = PHAssetCollection.fetchAssetCollections(
                    with: .smartAlbum, subtype: subtype, options: nil
                ).firstObject {
                    ids += identifiers(of: MediaFetch.collection(album))
                }
            }
            types.append(NSPredicate(format: "localIdentifier IN %@", ids))
        }
        if !types.isEmpty {
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: types))
        }

        if query.kinds.contains(.favorite) {
            predicates.append(NSPredicate(format: "localIdentifier IN %@", favorites))
        }
        if !query.terms.isEmpty {
            predicates.append(NSPredicate(format: "localIdentifier IN %@", assetIDs(inAlbumsMatching: query.terms)))
        }
        if let interval = query.date?.interval(in: calendar) {
            predicates.append(NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                interval.start as NSDate, interval.end as NSDate
            ))
        }
        let extra = predicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let result = PHAsset.fetchAssets(with: MediaFetch.options(extra))

        // A month without a year ("october") matches that month in every year. PhotoKit can't
        // filter by month alone, so the dates are checked here and the matches fetched by identifier.
        guard case .month = query.date, let date = query.date else { return result }
        var ids: [String] = []
        result.enumerateObjects { asset, _, _ in
            if let created = asset.creationDate, date.matches(created, in: calendar) {
                ids.append(asset.localIdentifier)
            }
        }
        return MediaFetch.identifiers(ids)
    }

    /// Identifiers of every visible item in albums whose names contain all the terms.
    nonisolated private static func assetIDs(inAlbumsMatching terms: [String]) -> [String] {
        var ids: [String] = []
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        collections.enumerateObjects { collection, _, _ in
            guard collection.assetCollectionSubtype != .albumCloudShared,
                  let title = collection.localizedTitle?.lowercased(),
                  terms.allSatisfy({ title.contains($0) })
            else { return }
            ids += identifiers(of: MediaFetch.collection(collection))
        }
        return ids
    }

    nonisolated private static func identifiers(of result: PHFetchResult<PHAsset>) -> [String] {
        var ids: [String] = []
        ids.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return ids
    }
}
