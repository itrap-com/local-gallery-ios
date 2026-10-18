import Photos

/// Forwards PhotoKit change notifications, which arrive on a background queue, to a handler.
final class LibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let handler: @Sendable (PHChange) -> Void

    init(handler: @escaping @Sendable (PHChange) -> Void) {
        self.handler = handler
        super.init()
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        handler(changeInstance)
    }
}
