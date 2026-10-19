import Photos
import SwiftUI

/// One grid cell. It asks for a size-capped thumbnail and never lets PhotoKit download an
/// iCloud-only original; such items show an "in iCloud" mark instead.
struct AssetTile: View {
    let asset: PHAsset
    let imageManager: PHCachingImageManager
    var isFavorite = false
    /// nil outside select mode.
    var isSelected: Bool? = nil

    @State private var image: UIImage?
    @State private var phase: Phase = .loading
    @State private var requestID: PHImageRequestID?

    private enum Phase {
        case loading
        case ready
        case inCloudOnly
        case failed
    }

    /// Thumbnails are capped at this pixel size, whatever the original's dimensions.
    static let thumbnailPixels = CGSize(width: 300, height: 300)

    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if phase == .inCloudOnly {
                    Image(systemName: "icloud")
                        .foregroundStyle(.secondary)
                } else if phase == .failed {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(5)
                }
            }
            .overlay {
                if isSelected == true {
                    Color.black.opacity(0.25)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let isSelected {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.2))
                        .shadow(radius: 2)
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Text(Self.durationText(asset.duration))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .onAppear(perform: load)
            .onDisappear(perform: cancel)
    }

    /// Generic on purpose: no filename, album or place ever reaches assistive technologies.
    private var accessibilityText: String {
        var text = asset.mediaType == .video
            ? "Video, \(Int(asset.duration.rounded())) seconds"
            : "Photo"
        if isSelected == true {
            text = "Selected " + text.lowercased()
        }
        if isFavorite {
            text += ", favorite"
        }
        if phase == .inCloudOnly {
            text += ", in iCloud, not on this iPhone"
        }
        return text
    }

    private func load() {
        guard image == nil, requestID == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        requestID = imageManager.requestImage(
            for: asset,
            targetSize: Self.thumbnailPixels,
            contentMode: .aspectFill,
            options: options
        ) { result, info in
            if let result {
                image = result
                phase = .ready
            } else if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
                phase = .inCloudOnly
            } else if info?[PHImageErrorKey] != nil {
                phase = .failed
            }
        }
    }

    private func cancel() {
        if let requestID {
            imageManager.cancelImageRequest(requestID)
        }
        requestID = nil
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%ld:%02ld", total / 60, total % 60)
    }
}
