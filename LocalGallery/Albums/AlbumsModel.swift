import Foundation
import Observation
import Photos

/// One row in the Albums tab.
struct AlbumSummary: Identifiable {
    enum Source {
        case favorites
        case collection(PHAssetCollection)
    }

    let id: String
    let title: String
    let symbol: String
    let count: Int
    let cover: PHAsset?
    let source: Source
}

/// Lists albums with their visible item counts and newest item as the cover.
///
/// Counts come from fetches of images and videos only, so they match what the grid shows under
/// limited access. Shared (iCloud) albums are left out: Gallery doesn't download anything.
@MainActor
@Observable
final class AlbumsModel {
    private(set) var system: [AlbumSummary] = []
    private(set) var user: [AlbumSummary] = []
    private(set) var isLoaded = false

    private let relay = ChangeRelay()
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var generation = 0

    init() {
        relay.onChange = { [weak self] _ in
            Task { @MainActor in
                self?.reload(favoriteIDs: nil)
            }
        }
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(relay)
    }

    @ObservationIgnored private var lastFavoriteIDs: [String] = []

    /// Pass nil to keep the last favorites list.
    func reload(favoriteIDs: [String]?) {
        if !isObserving {
            isObserving = true
            PHPhotoLibrary.shared().register(relay)
        }
        if let favoriteIDs {
            lastFavoriteIDs = favoriteIDs
        }
        generation += 1
        let token = generation
        let favorites = lastFavoriteIDs
        Task.detached(priority: .userInitiated) { [weak self] in
            let system = Self.loadSystem(favoriteIDs: favorites)
            let user = Self.loadUser()
            await self?.finish(system: system, user: user, token: token)
        }
    }

    private func finish(system: [AlbumSummary], user: [AlbumSummary], token: Int) {
        guard token == generation else { return }
        self.system = system
        self.user = user
        isLoaded = true
    }

    nonisolated private static let smartAlbums: [(PHAssetCollectionSubtype, String, String)] = [
        (.smartAlbumVideos, "Videos", "video"),
        (.smartAlbumSelfPortraits, "Selfies", "person.crop.square"),
        (.smartAlbumLivePhotos, "Live Photos", "livephoto"),
        (.smartAlbumScreenshots, "Screenshots", "camera.viewfinder"),
        (.smartAlbumPanoramas, "Panoramas", "pano"),
        (.smartAlbumSlomoVideos, "Slo-mo", "slowmo"),
        (.smartAlbumTimelapses, "Time-lapse", "timelapse"),
        (.smartAlbumBursts, "Bursts", "square.stack.3d.down.right"),
        (.smartAlbumDepthEffect, "Portrait", "cube"),
        (.smartAlbumAnimated, "Animated", "square.stack"),
        (.smartAlbumRAW, "RAW", "r.square"),
    ]

    nonisolated private static func loadSystem(favoriteIDs: [String]) -> [AlbumSummary] {
        var rows: [AlbumSummary] = []
        let favorites = MediaFetch.identifiers(favoriteIDs)
        rows.append(AlbumSummary(
            id: "favorites",
            title: "Favorites",
            symbol: "heart",
            count: favorites.count,
            cover: favorites.firstObject,
            source: .favorites
        ))
        for (subtype, title, symbol) in smartAlbums {
            guard let collection = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: subtype, options: nil
            ).firstObject else { continue }
            let assets = MediaFetch.collection(collection)
            guard assets.count > 0 else { continue }
            rows.append(AlbumSummary(
                id: collection.localIdentifier,
                title: title,
                symbol: symbol,
                count: assets.count,
                cover: assets.firstObject,
                source: .collection(collection)
            ))
        }
        return rows
    }

    nonisolated private static func loadUser() -> [AlbumSummary] {
        var rows: [AlbumSummary] = []
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        collections.enumerateObjects { collection, _, _ in
            guard collection.assetCollectionSubtype != .albumCloudShared,
                  collection.assetCollectionSubtype != .albumMyPhotoStream
            else { return }
            let assets = MediaFetch.collection(collection)
            guard assets.count > 0 else { return }
            rows.append(AlbumSummary(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "Untitled album",
                symbol: "rectangle.stack",
                count: assets.count,
                cover: assets.firstObject,
                source: .collection(collection)
            ))
        }
        return rows.sorted { lhs, rhs in
            (lhs.cover?.creationDate ?? .distantPast) > (rhs.cover?.creationDate ?? .distantPast)
        }
    }
}
