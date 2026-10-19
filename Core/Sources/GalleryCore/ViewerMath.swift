import Foundation

/// Pixel dimensions as PhotoKit reports them. Zero or negative means unknown.
public struct PixelSize: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var isKnown: Bool { width > 0 && height > 0 }
}

/// Platform-free rules behind the full-screen viewer.
public enum ViewerMath {
    /// The largest edge the viewer ever asks PhotoKit to decode. Zoom stays sharp on a phone screen,
    /// while a huge panorama cannot exhaust memory.
    public static let maxDecodeEdge = 4096

    /// The size to request for full-screen display: the original's size with the long edge capped,
    /// keeping the aspect ratio. Never upscales. Returns nil when the dimensions are unknown, so the
    /// caller falls back to a screen-sized request instead of inventing a shape.
    public static func decodeSize(for original: PixelSize, maxEdge: Int = maxDecodeEdge) -> PixelSize? {
        guard original.isKnown, maxEdge > 0 else { return nil }
        let longEdge = max(original.width, original.height)
        guard longEdge > maxEdge else { return original }
        let scale = Double(maxEdge) / Double(longEdge)
        return PixelSize(
            width: max(1, Int((Double(original.width) * scale).rounded())),
            height: max(1, Int((Double(original.height) * scale).rounded()))
        )
    }

    /// "4032 × 3024", or nil when unknown. The details sheet never shows "0 × 0".
    public static func dimensionsText(_ size: PixelSize) -> String? {
        size.isKnown ? "\(size.width) × \(size.height)" : nil
    }

    /// "37.33182° N, 122.03118° W", or nil for coordinates that are out of range or not numbers.
    /// Formatting only: nothing is looked up, so no place name is ever resolved.
    public static func coordinateText(latitude: Double, longitude: Double) -> String? {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return nil }
        let lat = String(format: "%.5f", abs(latitude)) + "° " + (latitude < 0 ? "S" : "N")
        let lon = String(format: "%.5f", abs(longitude)) + "° " + (longitude < 0 ? "W" : "E")
        return "\(lat), \(lon)"
    }

    /// Indexes whose images are worth preparing around the visible page.
    public static func neighbors(of index: Int, count: Int, radius: Int = 2) -> [Int] {
        guard count > 0, (0..<count).contains(index), radius > 0 else { return [] }
        let lower = max(0, index - radius)
        let upper = min(count - 1, index + radius)
        return (lower...upper).filter { $0 != index }
    }

    /// How far a swipe-down has progressed toward closing the viewer, from 0 to 1.
    public static func dismissProgress(translation: Double, viewHeight: Double) -> Double {
        guard viewHeight > 0, translation > 0 else { return 0 }
        return min(1, translation / (viewHeight * 0.4))
    }

    /// A downward swipe closes the viewer when it travels far enough or is flicked fast enough.
    public static func shouldDismiss(translation: Double, velocity: Double, viewHeight: Double) -> Bool {
        guard translation > 0 else { return false }
        return translation > viewHeight * 0.18 || velocity > 900
    }
}
