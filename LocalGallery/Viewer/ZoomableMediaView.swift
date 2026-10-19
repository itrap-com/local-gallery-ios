import AVFoundation
import GalleryCore
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// A still or Live Photo that pinches and double-taps to zoom, and swipes down to close.
///
/// UIKit owns the gestures here: a UIScrollView zooms and pans natively, and nests correctly inside
/// the viewer's horizontal pager.
struct ZoomableMedia: UIViewRepresentable {
    let image: UIImage?
    let livePhoto: PHLivePhoto?
    /// The original's pixel size, used for the layout before any image arrives.
    let pixelSize: PixelSize
    let isActive: Bool
    let onTap: () -> Void
    let onZoomChange: (Bool) -> Void
    let onDismissProgress: (Double) -> Void
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> ZoomableMediaView {
        ZoomableMediaView()
    }

    func updateUIView(_ view: ZoomableMediaView, context: Context) {
        view.onTap = onTap
        view.onZoomChange = onZoomChange
        view.onDismissProgress = onDismissProgress
        view.onDismiss = onDismiss
        view.show(image: image, livePhoto: livePhoto, pixelSize: pixelSize)
        if !isActive {
            view.resetZoom()
        }
    }
}

final class ZoomableMediaView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate, PHLivePhotoViewDelegate {
    var onTap: () -> Void = {}
    var onZoomChange: (Bool) -> Void = { _ in }
    var onDismissProgress: (Double) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    private let scrollView = UIScrollView()
    private let container = UIView()
    private let imageView = UIImageView()
    private let liveView = PHLivePhotoView()
    private var dismissPan: UIPanGestureRecognizer!

    private var contentAspect = CGSize(width: 1, height: 1)
    private var lastLayoutSize = CGSize.zero
    private var wasZoomed = false
    private weak var shownLivePhoto: PHLivePhoto?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.bouncesZoom = true
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(scrollView)

        scrollView.addSubview(container)
        imageView.contentMode = .scaleAspectFit
        // Lets HDR stills use the display's extended range here; the grid stays SDR.
        imageView.preferredImageDynamicRange = .high
        imageView.frame = container.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(imageView)

        liveView.contentMode = .scaleAspectFit
        liveView.frame = container.bounds
        liveView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // The Live Photo view only shows while its motion plays; at rest the sharper full-resolution
        // still underneath stays visible. Hidden views take no touches, so a long press here starts
        // playback instead of the view's own gesture.
        liveView.isHidden = true
        liveView.delegate = self
        container.addSubview(liveView)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.25
        addGestureRecognizer(longPress)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)

        dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        dismissPan.delegate = self
        addGestureRecognizer(dismissPan)

        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(image: UIImage?, livePhoto: PHLivePhoto?, pixelSize: PixelSize) {
        let aspect: CGSize
        if pixelSize.isKnown {
            aspect = CGSize(width: pixelSize.width, height: pixelSize.height)
        } else if let image, image.size.width > 0, image.size.height > 0 {
            aspect = image.size
        } else {
            aspect = contentAspect
        }
        if aspect != contentAspect {
            contentAspect = aspect
            lastLayoutSize = .zero
            setNeedsLayout()
        }
        if imageView.image !== image {
            imageView.image = image
        }
        if let livePhoto {
            if shownLivePhoto !== livePhoto {
                liveView.livePhoto = livePhoto
                shownLivePhoto = livePhoto
                liveView.startPlayback(with: .hint)
            }
        } else if shownLivePhoto != nil {
            liveView.stopPlayback()
            liveView.livePhoto = nil
            shownLivePhoto = nil
            liveView.isHidden = true
        }
    }

    func resetZoom() {
        guard scrollView.zoomScale != scrollView.minimumZoomScale else { return }
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLayoutSize, bounds.width > 0, bounds.height > 0 else { return }
        lastLayoutSize = bounds.size
        scrollView.zoomScale = 1
        let fitted = AVMakeRect(aspectRatio: contentAspect, insideRect: bounds).size
        container.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = fitted
        updateMaximumZoom()
        centerContent()
        scrollView.contentOffset = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
    }

    /// Lets zoom reach at least the original's own pixels, and never less than 4x.
    private func updateMaximumZoom() {
        let screenScale = traitCollection.displayScale
        guard container.bounds.width > 0, screenScale > 0 else { return }
        let pixelZoom = contentAspect.width / (container.bounds.width * screenScale)
        scrollView.maximumZoomScale = max(4, pixelZoom)
    }

    private func centerContent() {
        let size = scrollView.bounds.size
        let content = scrollView.contentSize
        let dx = max(0, (size.width - content.width) / 2)
        let dy = max(0, (size.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        container
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        if zoomed != wasZoomed {
            wasZoomed = zoomed
            onZoomChange(zoomed)
        }
    }

    // MARK: Gestures

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard shownLivePhoto != nil else { return }
        switch gesture.state {
        case .began:
            liveView.startPlayback(with: .full)
        case .ended, .cancelled, .failed:
            liveView.stopPlayback()
        default:
            break
        }
    }

    // MARK: PHLivePhotoViewDelegate

    func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
        livePhotoView.isHidden = false
    }

    func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
        livePhotoView.isHidden = true
    }

    @objc private func handleSingleTap() {
        onTap()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let point = gesture.location(in: container)
        let scale = min(scrollView.maximumZoomScale, 2.5)
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        scrollView.zoom(to: rect, animated: true)
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let height = Double(bounds.height)
        switch gesture.state {
        case .changed:
            let progress = ViewerMath.dismissProgress(translation: Double(translation.y), viewHeight: height)
            let scale = 1 - 0.25 * progress
            container.transform = CGAffineTransform(translationX: translation.x, y: max(0, translation.y))
                .scaledBy(x: scale, y: scale)
            onDismissProgress(progress)
        case .ended:
            let velocity = Double(gesture.velocity(in: self).y)
            if ViewerMath.shouldDismiss(translation: Double(translation.y), velocity: velocity, viewHeight: height) {
                onDismiss()
            } else {
                springBack()
            }
        case .cancelled, .failed:
            springBack()
        default:
            break
        }
    }

    private func springBack() {
        UIView.animate(
            withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: []
        ) {
            self.container.transform = .identity
        }
        onDismissProgress(0)
    }

    /// The close swipe starts only at normal zoom and only for a mostly downward drag, so pinching,
    /// panning a zoomed photo and paging sideways keep working.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPan else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else { return false }
        let velocity = dismissPan.velocity(in: self)
        return velocity.y > 0 && abs(velocity.y) > abs(velocity.x) * 1.2
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // The pager's pan barely moves on a downward drag, so letting both run keeps the close
        // swipe from losing the gesture to it.
        gestureRecognizer === dismissPan
    }
}
