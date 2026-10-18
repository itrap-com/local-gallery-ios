import Foundation
import GalleryCore
import Observation
import Photos
import UIKit

enum LibraryContent: Equatable {
    case idle
    case loading
    case loaded
    case unavailable
}

/// Owns the PhotoKit fetch behind the timeline.
///
/// It only reads: nothing is written to the photo library, and thumbnail requests never allow
/// network access, so iCloud-only originals are shown as such instead of being downloaded.
@MainActor
@Observable
final class PhotoLibraryModel {
    private(set) var access: LibraryAccess
    private(set) var content: LibraryContent = .idle
    private(set) var assets: PHFetchResult<PHAsset>?
    private(set) var sections: [TimelineSection] = []

    let imageManager = PHCachingImageManager()

    @ObservationIgnored private var changeObserver: LibraryChangeObserver?
    @ObservationIgnored private var generation = 0

    init() {
        access = LibraryAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// Re-reads authorization and availability. Runs at launch and whenever the app becomes active,
    /// so a change made in Settings takes effect without a restart.
    func refreshAccess() {
        let current = LibraryAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        let changed = current != access
        access = current

        guard current.canRead else {
            stopObserving()
            assets = nil
            sections = []
            content = .idle
            return
        }
        if PHPhotoLibrary.shared().unavailabilityReason != nil {
            content = .unavailable
            return
        }
        startObserving()
        if changed || assets == nil || content == .unavailable {
            reload()
        }
    }

    func requestAccess() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        refreshAccess()
    }

    /// Lets the user change a limited selection from inside Gallery instead of a system nag.
    func presentLimitedLibraryPicker() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }

    private func reload() {
        if assets == nil {
            content = .loading
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        install(PHAsset.fetchAssets(with: options))
    }

    /// Groups a fetch result off the main thread, then swaps the result and its sections in
    /// together, so the grid never indexes past the end of a stale result.
    private func install(_ result: PHFetchResult<PHAsset>) {
        generation += 1
        let token = generation
        let calendar = Calendar.current
        Task.detached(priority: .userInitiated) { [weak self] in
            var dates: [Date?] = []
            dates.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                dates.append(asset.creationDate)
            }
            let sections = TimelineGrouping.monthSections(dates: dates, calendar: calendar)
            await self?.finishInstall(result, sections: sections, token: token)
        }
    }

    private func finishInstall(_ result: PHFetchResult<PHAsset>, sections: [TimelineSection], token: Int) {
        guard token == generation else { return }
        assets = result
        self.sections = sections
        content = .loaded
    }

    private func startObserving() {
        guard changeObserver == nil else { return }
        let observer = LibraryChangeObserver { [weak self] change in
            Task { @MainActor in
                self?.apply(change)
            }
        }
        PHPhotoLibrary.shared().register(observer)
        changeObserver = observer
    }

    private func stopObserving() {
        guard let observer = changeObserver else { return }
        PHPhotoLibrary.shared().unregisterChangeObserver(observer)
        changeObserver = nil
    }

    private func apply(_ change: PHChange) {
        guard let current = assets, let details = change.changeDetails(for: current) else { return }
        install(details.fetchResultAfterChanges)
    }
}
