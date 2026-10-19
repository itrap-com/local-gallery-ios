import Foundation
import GalleryCore
import Observation
import Photos
import PhotosUI
import UIKit

/// App-wide library state: what iOS lets Gallery read, the shared image cache and the app-local
/// favorites. Each grid owns its own `MediaFeed`.
///
/// The only writes to the photo library are deletes, and iOS asks the owner to confirm each one.
/// Image requests never allow network access, so iCloud-only originals are never downloaded.
@MainActor
@Observable
final class PhotoLibraryModel {
    private(set) var access: LibraryAccess
    private(set) var isUnavailable = false
    /// Changes whenever access changes, so feeds know to fetch again.
    private(set) var accessGeneration = 0

    /// Grid columns, shared by every grid; pinch or the Library menu changes it.
    var gridColumns = 4

    let imageManager = PHCachingImageManager()
    let favorites = FavoritesStore()

    init() {
        access = LibraryAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// Re-reads authorization and availability. Runs at launch and whenever the app becomes active,
    /// so a change made in Settings takes effect without a restart.
    func refreshAccess() {
        let current = LibraryAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        let unavailable = current.canRead && PHPhotoLibrary.shared().unavailabilityReason != nil
        if current != access || unavailable != isUnavailable {
            access = current
            isUnavailable = unavailable
            accessGeneration += 1
        }
    }

    func requestAccess() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        refreshAccess()
    }

    /// Lets the user change a limited selection from inside Gallery instead of a system nag.
    func presentLimitedLibraryPicker() {
        guard let top = Self.topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }

    /// Deletes through PhotoKit, which shows its own confirmation. Returns false when the owner
    /// cancels; throws for other failures.
    func delete(_ assets: [PHAsset]) async throws -> Bool {
        guard !assets.isEmpty else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            favorites.remove(assets.map(\.localIdentifier))
            return true
        } catch let error as PHPhotosError where error.code == .userCancelled {
            return false
        }
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

/// App-local favorites, saved in Gallery's own container. Nothing is written to the photo library
/// and nothing syncs anywhere.
@MainActor
@Observable
final class FavoritesStore {
    private(set) var list = FavoriteList()
    /// False when the saved file came from a newer Gallery, so this one never overwrites it.
    @ObservationIgnored private var writable = true

    init() {
        load()
    }

    func contains(_ asset: PHAsset) -> Bool {
        list.contains(asset.localIdentifier)
    }

    func toggle(_ assets: [PHAsset]) {
        list.toggle(assets.map(\.localIdentifier))
        save()
    }

    func remove(_ ids: [String]) {
        list.remove(ids)
        save()
    }

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("favorites.json", isDirectory: false)
    }

    private func load() {
        guard let url = Self.fileURL, let data = try? Data(contentsOf: url) else { return }
        do {
            if let stored = try FavoriteList.decode(data) {
                list = stored
            } else {
                writable = false
            }
        } catch {
            // A damaged file is kept aside rather than silently replaced by an empty list.
            let aside = url.deletingPathExtension().appendingPathExtension("damaged.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
        }
    }

    private func save() {
        guard writable, let url = Self.fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try list.encoded().write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            // Favorites stay correct in memory for this session; the next change retries the save.
        }
    }
}
