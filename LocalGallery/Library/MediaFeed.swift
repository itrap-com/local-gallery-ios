import Foundation
import GalleryCore
import Observation
import Photos

/// One live list of photos and videos: the whole timeline, an album, the favorites or a search.
///
/// The fetch runs off the main thread, and the result is grouped into month sections there too.
/// The new result and its sections swap in together, so a grid never indexes past the end of a
/// stale list. The feed follows library changes until it is released.
@MainActor
@Observable
final class MediaFeed {
    typealias Fetch = @Sendable () -> PHFetchResult<PHAsset>

    private(set) var assets: PHFetchResult<PHAsset>?
    private(set) var sections: [TimelineSection] = []
    private(set) var isLoaded = false

    /// Whether the grid shows month headers. Album and search grids are still sorted by date.
    let showsMonths: Bool

    @ObservationIgnored private var fetch: Fetch
    @ObservationIgnored private var generation = 0
    private let relay = ChangeRelay()
    @ObservationIgnored private var isObserving = false

    init(showsMonths: Bool = true, fetch: @escaping Fetch) {
        self.showsMonths = showsMonths
        self.fetch = fetch
        relay.onChange = { [weak self] change in
            Task { @MainActor in
                self?.apply(change)
            }
        }
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(relay)
    }

    /// Loads the first time it is called; later calls do nothing.
    func loadIfNeeded() {
        if assets == nil, generation == 0 {
            reload()
        }
    }

    /// Fetches again, for example after access changed or the query did.
    func reload() {
        // Registered on first use, not in init: SwiftUI may create and discard feeds while it
        // rebuilds views, and those should cost nothing.
        if !isObserving {
            isObserving = true
            PHPhotoLibrary.shared().register(relay)
        }
        let fetch = self.fetch
        run { fetch() }
    }

    /// Replaces the query and fetches with it.
    func update(_ fetch: @escaping Fetch) {
        self.fetch = fetch
        reload()
    }

    private func apply(_ change: PHChange) {
        guard let current = assets else { return }
        if let details = change.changeDetails(for: current) {
            let next = details.fetchResultAfterChanges
            run { next }
        }
    }

    private func run(_ produce: @escaping @Sendable () -> PHFetchResult<PHAsset>) {
        generation += 1
        let token = generation
        let calendar = Calendar.current
        let grouped = showsMonths
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = produce()
            let sections: [TimelineSection]
            if grouped {
                var dates: [Date?] = []
                dates.reserveCapacity(result.count)
                result.enumerateObjects { asset, _, _ in
                    dates.append(asset.creationDate)
                }
                sections = TimelineGrouping.monthSections(dates: dates, calendar: calendar)
            } else {
                sections = result.count > 0 ? [TimelineSection(month: nil, range: 0..<result.count)] : []
            }
            await self?.finish(result, sections: sections, token: token)
        }
    }

    private func finish(_ result: PHFetchResult<PHAsset>, sections: [TimelineSection], token: Int) {
        guard token == generation else { return }
        assets = result
        self.sections = sections
        isLoaded = true
    }
}

/// Forwards PhotoKit change notifications, which arrive on a background queue. The handler is set
/// once, before registration, and never changes.
final class ChangeRelay: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    var onChange: (@Sendable (PHChange) -> Void)?

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange?(changeInstance)
    }
}

/// Fetch descriptions shared by every feed: images and videos only, newest first.
enum MediaFetch {
    static func options(_ extra: NSPredicate? = nil) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var predicates = [NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )]
        if let extra {
            predicates.append(extra)
        }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return options
    }

    static func all(_ filter: MediaFilter = .all) -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(with: options(filter.predicate))
    }

    static func identifiers(_ ids: [String]) -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options())
    }

    static func collection(_ collection: PHAssetCollection) -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(in: collection, options: options())
    }
}

/// The Library tab's type filter.
enum MediaFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case photos
    case videos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All items"
        case .photos: "Photos"
        case .videos: "Videos"
        }
    }

    var predicate: NSPredicate? {
        switch self {
        case .all: nil
        case .photos: NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        case .videos: NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        }
    }
}
