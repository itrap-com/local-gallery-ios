import AVFoundation
import AVKit
import Photos
import SwiftUI

/// One video in the viewer, played by the system player with its native controls.
///
/// The poster frame shows at once; the player item is requested only for the visible page and is
/// released when the page leaves, so paging never keeps several decoders alive. iCloud-only videos
/// are never downloaded. Playback doesn't publish lock-screen "Now Playing" details.
struct VideoPage: View {
    let asset: PHAsset
    let imageManager: PHCachingImageManager
    let isCurrent: Bool
    let showsChrome: Bool

    @State private var poster: UIImage?
    @State private var player: AVPlayer?
    @State private var posterRequest: PHImageRequestID?
    @State private var playerRequest: PHImageRequestID?
    @State private var unavailable: Unavailable?

    private enum Unavailable {
        case inCloud
        case unplayable
    }

    var body: some View {
        ZStack {
            if let poster, player == nil {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
            }
            if let player {
                SystemVideoPlayer(player: player)
            }
            if unavailable == .unplayable, poster == nil {
                UnavailableMediaNotice(
                    symbol: "exclamationmark.triangle",
                    text: "This video can't be played. It may be damaged or use a format this iPhone can't play."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if showsChrome, player == nil {
                switch unavailable {
                case .inCloud:
                    ViewerNote(text: "This video is in iCloud and Gallery doesn't download it.")
                case .unplayable:
                    if poster != nil {
                        ViewerNote(text: "This video can't be played on this iPhone.")
                    }
                case nil:
                    EmptyView()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video, \(Int(asset.duration.rounded())) seconds")
        .onAppear(perform: loadPoster)
        .onDisappear {
            if let posterRequest {
                imageManager.cancelImageRequest(posterRequest)
            }
            posterRequest = nil
            releasePlayer()
        }
        .onChange(of: isCurrent, initial: true) { _, current in
            if current {
                loadPlayer()
            } else {
                releasePlayer()
            }
        }
    }

    private func loadPoster() {
        guard poster == nil, posterRequest == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        posterRequest = imageManager.requestImage(
            for: asset,
            targetSize: PhotoPage.screenPixels,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            if let result {
                poster = result
            }
        }
    }

    private func loadPlayer() {
        guard player == nil, playerRequest == nil else { return }
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = false
        // The result handler runs on an arbitrary queue; state changes hop to the main actor. A
        // released page clears playerRequest first, so a late result is dropped.
        playerRequest = imageManager.requestPlayerItem(forVideo: asset, options: options) { item, info in
            let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
            Task { @MainActor in
                guard playerRequest != nil else { return }
                playerRequest = nil
                if let item {
                    Self.preparePlaybackAudio()
                    player = AVPlayer(playerItem: item)
                    unavailable = nil
                } else {
                    unavailable = inCloud ? .inCloud : .unplayable
                }
            }
        }
    }

    private func releasePlayer() {
        if let playerRequest {
            imageManager.cancelImageRequest(playerRequest)
        }
        playerRequest = nil
        player?.pause()
        player = nil
    }

    /// Video sound plays even with the silent switch on, and other audio pauses, as in Photos.
    /// If the category can't be set, playback still works with the system default.
    private static func preparePlaybackAudio() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }
}

/// The system player view controller, kept inline (no automatic full screen).
private struct SystemVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.updatesNowPlayingInfoCenter = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
