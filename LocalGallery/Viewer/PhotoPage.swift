import GalleryCore
import Photos
import SwiftUI

/// One still or Live Photo in the viewer.
///
/// It paints the grid's cached thumbnail first, then a screen-sized image, then, only while it is
/// the visible page, the full-resolution decode (capped by `ViewerMath.maxDecodeEdge`). Neighbours
/// drop their full-resolution image, so paging never holds several huge bitmaps. iCloud originals
/// are never downloaded: such items keep the best local image and say so.
struct PhotoPage: View {
    let asset: PHAsset
    let imageManager: PHCachingImageManager
    let isCurrent: Bool
    let showsChrome: Bool
    let onTap: () -> Void
    let onZoomChange: (Bool) -> Void
    let onDismissProgress: (Double) -> Void
    let onDismiss: () -> Void

    @State private var thumbnail: UIImage?
    @State private var screenImage: UIImage?
    @State private var fullImage: UIImage?
    @State private var livePhoto: PHLivePhoto?
    @State private var originalInCloud = false
    @State private var failed = false
    @State private var previewRequests: [PHImageRequestID] = []
    @State private var fullRequests: [PHImageRequestID] = []

    private var pixelSize: PixelSize {
        PixelSize(width: asset.pixelWidth, height: asset.pixelHeight)
    }

    var body: some View {
        ZStack {
            ZoomableMedia(
                image: fullImage ?? screenImage ?? thumbnail,
                livePhoto: livePhoto,
                pixelSize: pixelSize,
                isActive: isCurrent,
                onTap: onTap,
                onZoomChange: onZoomChange,
                onDismissProgress: onDismissProgress,
                onDismiss: onDismiss
            )
            if failed, thumbnail == nil, screenImage == nil {
                UnavailableMediaNotice(
                    symbol: "exclamationmark.triangle",
                    text: "This photo can't be shown. It may be damaged or in a format this iPhone can't read."
                )
            }
        }
        .overlay(alignment: .bottom) {
            if originalInCloud, showsChrome {
                ViewerNote(text: "Showing a preview. The original is in iCloud and Gallery doesn't download it.")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(asset.mediaSubtypes.contains(.photoLive) ? "Live Photo" : "Photo")
        .accessibilityAddTraits(.isImage)
        .onAppear(perform: loadPreview)
        .onDisappear {
            previewRequests.forEach(imageManager.cancelImageRequest)
            previewRequests = []
            releaseFull()
        }
        .onChange(of: isCurrent, initial: true) { _, current in
            if current {
                loadFull()
            } else {
                releaseFull()
            }
        }
    }

    private func loadPreview() {
        guard previewRequests.isEmpty, screenImage == nil else { return }
        let thumbOptions = PHImageRequestOptions()
        thumbOptions.deliveryMode = .opportunistic
        thumbOptions.resizeMode = .fast
        thumbOptions.isNetworkAccessAllowed = false
        previewRequests.append(imageManager.requestImage(
            for: asset,
            targetSize: AssetTile.thumbnailPixels,
            contentMode: .aspectFill,
            options: thumbOptions
        ) { result, _ in
            if let result, screenImage == nil {
                thumbnail = result
            }
        })

        let screenOptions = PHImageRequestOptions()
        screenOptions.deliveryMode = .opportunistic
        screenOptions.resizeMode = .fast
        screenOptions.isNetworkAccessAllowed = false
        previewRequests.append(imageManager.requestImage(
            for: asset,
            targetSize: Self.screenPixels,
            contentMode: .aspectFit,
            options: screenOptions
        ) { result, info in
            if let result {
                screenImage = result
            } else if info?[PHImageErrorKey] != nil {
                failed = true
            }
        })
    }

    private func loadFull() {
        guard fullRequests.isEmpty, fullImage == nil else { return }
        let target = ViewerMath.decodeSize(for: pixelSize).map {
            CGSize(width: $0.width, height: $0.height)
        } ?? Self.screenPixels

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false
        fullRequests.append(imageManager.requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { result, info in
            if let result {
                fullImage = result
            } else if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
                originalInCloud = true
            }
        })

        guard asset.mediaSubtypes.contains(.photoLive) else { return }
        let liveOptions = PHLivePhotoRequestOptions()
        liveOptions.deliveryMode = .highQualityFormat
        liveOptions.isNetworkAccessAllowed = false
        fullRequests.append(imageManager.requestLivePhoto(
            for: asset,
            targetSize: Self.screenPixels,
            contentMode: .aspectFit,
            options: liveOptions
        ) { result, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            if let result, !degraded {
                livePhoto = result
            }
        })
    }

    private func releaseFull() {
        fullRequests.forEach(imageManager.cancelImageRequest)
        fullRequests = []
        fullImage = nil
        livePhoto = nil
    }

    /// About a phone screen's long edge in pixels: sharp enough for the fast first image and for
    /// Live Photo frames, while the visible page swaps in the full decode.
    static let screenPixels = CGSize(width: 2048, height: 2048)
}

/// A short line at the bottom of a viewer page, legible over any photo.
struct ViewerNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
    }
}

/// Shown in place of media that can't be decoded or played.
struct UnavailableMediaNotice: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.largeTitle)
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(32)
    }
}
