import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import GalleryCore
import ImageIO

/// Turns an `EditRecipe` into pixels. The preview and the saved file go through the same steps,
/// so what the owner sees is what gets saved; only the input size differs.
enum EditRenderer {
    /// Shared and thread-safe; creating a context per render would be slow.
    static let context = CIContext(options: [.cacheIntermediates: false])

    /// Geometry, then color. With `includeCrop` false, the crop step is skipped, which is how the
    /// crop tool shows the whole picture around the crop box.
    static func render(_ input: CIImage, _ recipe: EditRecipe, includeCrop: Bool = true) -> CIImage {
        var image = input
        if recipe.autoEnhance {
            image = autoEnhanced(image)
        }
        image = geometry(image, recipe, includeCrop: includeCrop)
        return color(image, recipe)
    }

    // MARK: Geometry

    static func geometry(_ input: CIImage, _ recipe: EditRecipe, includeCrop: Bool) -> CIImage {
        var image = normalized(input)

        let turns = ((recipe.quarterTurns % 4) + 4) % 4
        for _ in 0..<turns {
            // A clockwise quarter turn in Core Image's y-up space, as an exact matrix: a computed
            // rotation leaves tiny cosine errors that grow the extent by a pixel.
            image = normalized(image.transformed(by: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)))
        }
        if recipe.flipped {
            image = normalized(image.transformed(by: CGAffineTransform(scaleX: -1, y: 1)))
        }
        if abs(recipe.straighten) >= 0.01 {
            image = straightened(image, degrees: recipe.straighten)
        }
        if includeCrop, !recipe.crop.isFull {
            let size = image.extent.size
            let r = EditGeometry.pixelRect(recipe.crop, width: size.width, height: size.height)
            image = normalized(image.cropped(to: CGRect(x: r.x, y: r.y, width: r.width, height: r.height)))
        }
        return image
    }

    /// Turns the picture about its centre and enlarges it just enough to fill the same frame.
    private static func straightened(_ image: CIImage, degrees: Double) -> CIImage {
        let frame = image.extent
        let scale = EditGeometry.straightenScale(width: frame.width, height: frame.height, degrees: degrees)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: -degrees * .pi / 180)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -center.x, y: -center.y)
        return normalized(image.clampedToExtent().transformed(by: transform).cropped(to: frame))
    }

    /// Moves the image's origin to (0, 0) and snaps its extent to whole pixels.
    private static func normalized(_ image: CIImage) -> CIImage {
        let extent = image.extent.integral
        return image.cropped(to: extent).transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }

    // MARK: Color

    static func color(_ input: CIImage, _ recipe: EditRecipe) -> CIImage {
        var image = input
        let extent = input.extent

        if let filter = recipe.filter {
            image = preset(filter, image)
        }

        let exposure = recipe[.exposure]
        if exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = image
            f.ev = Float(exposure * 2)
            image = f.outputImage ?? image
        }

        let brightness = recipe[.brightness]
        let contrast = recipe[.contrast]
        let saturation = recipe[.saturation]
        if brightness != 0 || contrast != 0 || saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.brightness = Float(brightness * 0.25)
            f.contrast = Float(1 + contrast * 0.5)
            f.saturation = Float(1 + saturation)
            image = f.outputImage ?? image
        }

        let highlights = recipe[.highlights]
        let shadows = recipe[.shadows]
        if highlights != 0 || shadows != 0 {
            let f = CIFilter.toneCurve()
            f.inputImage = image
            f.point0 = CGPoint(x: 0, y: 0)
            f.point1 = CGPoint(x: 0.25, y: 0.25 + shadows * 0.12)
            f.point2 = CGPoint(x: 0.5, y: 0.5 + (shadows + highlights) * 0.03)
            f.point3 = CGPoint(x: 0.75, y: 0.75 + highlights * 0.12)
            f.point4 = CGPoint(x: 1, y: 1)
            image = f.outputImage ?? image
        }

        let vibrance = recipe[.vibrance]
        if vibrance != 0 {
            let f = CIFilter.vibrance()
            f.inputImage = image
            f.amount = Float(vibrance)
            image = f.outputImage ?? image
        }

        let warmth = recipe[.warmth]
        let tint = recipe[.tint]
        if warmth != 0 || tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            // Claiming a bluer source light makes the correction warm the picture.
            f.neutral = CIVector(x: 6500 + warmth * 2000, y: tint * 60)
            f.targetNeutral = CIVector(x: 6500, y: 0)
            image = f.outputImage ?? image
        }

        let sharpness = recipe[.sharpness]
        if sharpness > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = image
            f.sharpness = Float(sharpness)
            f.radius = Float(max(1, min(extent.width, extent.height) / 1000))
            image = f.outputImage ?? image
        }

        let vignette = recipe[.vignette]
        if vignette > 0 {
            // Defined in pixels, so the preview and the full-size save darken the same area.
            let f = CIFilter.vignetteEffect()
            f.inputImage = image
            f.center = CGPoint(x: extent.midX, y: extent.midY)
            f.radius = Float(hypot(extent.width, extent.height) / 2 * 0.6)
            f.intensity = Float(vignette)
            f.falloff = 0.5
            image = f.outputImage ?? image
        }

        return image.cropped(to: extent)
    }

    private static func preset(_ preset: FilterPreset, _ image: CIImage) -> CIImage {
        let name: String
        switch preset {
        case .mono: name = "CIPhotoEffectMono"
        case .noir: name = "CIPhotoEffectNoir"
        case .tonal: name = "CIPhotoEffectTonal"
        case .chrome: name = "CIPhotoEffectChrome"
        case .fade: name = "CIPhotoEffectFade"
        case .instant: name = "CIPhotoEffectInstant"
        case .process: name = "CIPhotoEffectProcess"
        case .transfer: name = "CIPhotoEffectTransfer"
        }
        guard let filter = CIFilter(name: name) else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }

    private static func autoEnhanced(_ image: CIImage) -> CIImage {
        var output = image
        for filter in image.autoAdjustmentFilters(options: [.redEye: false]) {
            filter.setValue(output, forKey: kCIInputImageKey)
            output = filter.outputImage ?? output
        }
        return output
    }

    // MARK: Output

    /// Renders a CGImage for display, in the display P3 space.
    static func cgImage(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.displayP3))
    }

    /// Writes the edited full-size image as HEIC or JPEG, keeping the original's metadata (date,
    /// camera and location) except the orientation, which the pixels now carry.
    static func write(_ image: CIImage, properties: [String: Any], to url: URL, asHEIC: Bool) throws {
        var metadata = properties
        metadata[kCGImagePropertyOrientation as String] = 1
        if var tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            metadata[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        metadata.removeValue(forKey: kCGImagePropertyPixelWidth as String)
        metadata.removeValue(forKey: kCGImagePropertyPixelHeight as String)
        let output = image.settingProperties(metadata)
        let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        if asHEIC {
            try context.writeHEIFRepresentation(of: output, to: url, format: .RGBA8, colorSpace: space, options: [quality: 0.92])
        } else {
            try context.writeJPEGRepresentation(of: output, to: url, colorSpace: space, options: [quality: 0.92])
        }
    }
}
