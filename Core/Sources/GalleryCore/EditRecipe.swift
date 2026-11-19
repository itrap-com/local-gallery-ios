import Foundation

/// A rectangle in normalized image coordinates: 0...1 on both axes, origin at the top left.
public struct NormRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = NormRect(x: 0, y: 0, width: 1, height: 1)

    public var isFull: Bool {
        abs(x) < 1e-6 && abs(y) < 1e-6 && abs(width - 1) < 1e-6 && abs(height - 1) < 1e-6
    }
}

/// A tone or color adjustment. Values are unitless; `range` is the slider's span.
public enum Adjustment: String, CaseIterable, Codable, Sendable {
    case exposure
    case brightness
    case contrast
    case highlights
    case shadows
    case saturation
    case vibrance
    case warmth
    case tint
    case sharpness
    case vignette

    public var title: String {
        switch self {
        case .exposure: "Exposure"
        case .brightness: "Brightness"
        case .contrast: "Contrast"
        case .highlights: "Highlights"
        case .shadows: "Shadows"
        case .saturation: "Saturation"
        case .vibrance: "Vibrance"
        case .warmth: "Warmth"
        case .tint: "Tint"
        case .sharpness: "Sharpness"
        case .vignette: "Vignette"
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .sharpness, .vignette: 0...1
        default: -1...1
        }
    }
}

/// A one-tap look. The app maps each to a built-in Core Image effect.
public enum FilterPreset: String, CaseIterable, Codable, Sendable {
    case mono
    case noir
    case tonal
    case chrome
    case fade
    case instant
    case process
    case transfer

    public var title: String {
        switch self {
        case .mono: "Mono"
        case .noir: "Noir"
        case .tonal: "Tonal"
        case .chrome: "Chrome"
        case .fade: "Fade"
        case .instant: "Instant"
        case .process: "Process"
        case .transfer: "Transfer"
        }
    }
}

/// Every edit as data. The same recipe renders the preview and the saved file, and it is stored
/// with in-place edits so they can be reopened and adjusted, or reverted in Photos.
///
/// Geometry applies in this order: quarter turns (clockwise), horizontal flip, straighten, crop.
/// Color applies after geometry.
public struct EditRecipe: Codable, Equatable, Sendable {
    public var quarterTurns: Int = 0
    public var flipped = false
    /// Degrees, clockwise positive, within ±45.
    public var straighten: Double = 0
    /// In the turned, flipped and straightened image.
    public var crop: NormRect = .full
    public var autoEnhance = false
    public var filter: FilterPreset?
    /// Keyed by `Adjustment.rawValue`, so the stored JSON stays readable and stable.
    public var adjustments: [String: Double] = [:]

    public init() {}

    public subscript(_ adjustment: Adjustment) -> Double {
        get { adjustments[adjustment.rawValue] ?? 0 }
        set {
            let value = min(max(newValue, adjustment.range.lowerBound), adjustment.range.upperBound)
            adjustments[adjustment.rawValue] = abs(value) < 0.001 ? nil : value
        }
    }

    public var isIdentity: Bool {
        quarterTurns % 4 == 0 && !flipped && abs(straighten) < 0.01 && crop.isFull
            && !autoEnhance && filter == nil && adjustments.isEmpty
    }

    public var hasGeometry: Bool {
        quarterTurns % 4 != 0 || flipped || abs(straighten) >= 0.01 || !crop.isFull
    }

    /// Turns the picture a quarter clockwise on screen, carrying the crop with it. Turns are
    /// applied before the flip, so on a flipped picture a clockwise turn is stored as three.
    public mutating func rotateClockwise() {
        quarterTurns = (quarterTurns + (flipped ? 3 : 1)) % 4
        crop = EditGeometry.rotatedClockwise(crop)
    }

    /// Mirrors the picture left to right, carrying the crop with it. Straighten is applied after
    /// the flip, so its angle mirrors too.
    public mutating func flipHorizontally() {
        flipped.toggle()
        straighten = -straighten
        crop = EditGeometry.flippedHorizontally(crop)
    }

    // MARK: Storage format

    public static let formatIdentifier = "local-gallery.ios.edit"
    public static let formatVersion = "1"

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Reads stored edit data. Returns nil when the format or version isn't one this build writes,
    /// so the editor starts from the current image instead of misreading it.
    public static func decode(_ data: Data, formatIdentifier: String, formatVersion: String) -> EditRecipe? {
        guard formatIdentifier == Self.formatIdentifier, formatVersion == Self.formatVersion else { return nil }
        return try? JSONDecoder().decode(EditRecipe.self, from: data)
    }
}

/// Which corner of the crop box is being dragged.
public enum CropCorner: CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

/// Crop and straighten math, shared by the preview and the export.
public enum EditGeometry {
    /// The smallest crop side, as a fraction of the image.
    public static let minimumSide = 0.08

    /// How much a straightened image must be enlarged so it still fills its original frame.
    public static func straightenScale(width: Double, height: Double, degrees: Double) -> Double {
        guard width > 0, height > 0 else { return 1 }
        let angle = abs(degrees) * .pi / 180
        let c = cos(angle)
        let s = sin(angle)
        return max((width * c + height * s) / width, (width * s + height * c) / height)
    }

    /// The pixel size after quarter turns.
    public static func turnedSize(_ size: PixelSize, quarterTurns: Int) -> PixelSize {
        quarterTurns % 2 == 0 ? size : PixelSize(width: size.height, height: size.width)
    }

    /// The largest centred crop with the given width:height ratio, in an image of `imageAspect`.
    public static func centeredCrop(aspect: Double, imageAspect: Double) -> NormRect {
        guard aspect > 0, imageAspect > 0 else { return .full }
        let ratio = aspect / imageAspect
        let width = ratio >= 1 ? 1 : ratio
        let height = ratio >= 1 ? 1 / ratio : 1
        return NormRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    /// Where a crop lands after the picture turns a quarter clockwise.
    public static func rotatedClockwise(_ rect: NormRect) -> NormRect {
        NormRect(x: 1 - rect.y - rect.height, y: rect.x, width: rect.height, height: rect.width)
    }

    /// Where a crop lands after the picture is mirrored left to right.
    public static func flippedHorizontally(_ rect: NormRect) -> NormRect {
        NormRect(x: 1 - rect.x - rect.width, y: rect.y, width: rect.width, height: rect.height)
    }

    /// Moves the crop box, keeping it inside the image.
    public static func move(_ rect: NormRect, dx: Double, dy: Double) -> NormRect {
        NormRect(
            x: min(max(rect.x + dx, 0), 1 - rect.width),
            y: min(max(rect.y + dy, 0), 1 - rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    /// Drags one corner while the opposite corner stays put. `ratio` is the locked width:height
    /// ratio in normalized units, or nil for a free crop. The result stays inside the image and
    /// no side drops below `minimumSide`.
    public static func resize(_ rect: NormRect, corner: CropCorner, dx: Double, dy: Double, ratio: Double?) -> NormRect {
        let anchorX = corner.isLeft ? rect.x + rect.width : rect.x
        let anchorY = corner.isTop ? rect.y + rect.height : rect.y
        let movingX = (corner.isLeft ? rect.x : rect.x + rect.width) + dx
        let movingY = (corner.isTop ? rect.y : rect.y + rect.height) + dy
        let maxWidth = corner.isLeft ? anchorX : 1 - anchorX
        let maxHeight = corner.isTop ? anchorY : 1 - anchorY

        var width = min(max(corner.isLeft ? anchorX - movingX : movingX - anchorX, minimumSide), maxWidth)
        var height = min(max(corner.isTop ? anchorY - movingY : movingY - anchorY, minimumSide), maxHeight)
        if let ratio, ratio > 0 {
            if width / height > ratio {
                width = height * ratio
            } else {
                height = width / ratio
            }
            if width > maxWidth {
                width = maxWidth
                height = width / ratio
            }
            if height > maxHeight {
                height = maxHeight
                width = height * ratio
            }
        }
        return NormRect(
            x: corner.isLeft ? anchorX - width : anchorX,
            y: corner.isTop ? anchorY - height : anchorY,
            width: width,
            height: height
        )
    }

    /// The crop in pixels, with the origin at the bottom left as Core Image uses, rounded to whole
    /// pixels and never empty.
    public static func pixelRect(_ rect: NormRect, width: Double, height: Double) -> (x: Double, y: Double, width: Double, height: Double) {
        let w = max(1, (rect.width * width).rounded())
        let h = max(1, (rect.height * height).rounded())
        let x = min(max(0, (rect.x * width).rounded()), max(0, width - w))
        let yTop = min(max(0, (rect.y * height).rounded()), max(0, height - h))
        return (x, height - yTop - h, w, h)
    }
}
