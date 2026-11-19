import CoreImage
import Foundation
import GalleryCore
import ImageIO
import Observation
import Photos
import UniformTypeIdentifiers

/// State behind the photo editor: the source, the recipe with undo and redo, the live preview and
/// saving.
///
/// Saving in place writes the rendered photo plus the recipe as adjustment data, so Photos can
/// revert it and Gallery can reopen the edit. Save as Copy creates a new photo with the original's
/// date and location. Nothing is downloaded from iCloud.
@MainActor
@Observable
final class EditorModel {
    enum Phase: Equatable {
        case loading
        case ready
        case saving
        case failed(String)
    }

    let asset: PHAsset
    private(set) var phase: Phase = .loading
    private(set) var recipe = EditRecipe()
    private(set) var preview: CGImage?
    private(set) var original: CGImage?
    /// The preview source's aspect after quarter turns, for the crop box.
    private(set) var turnedAspect: Double = 1
    /// While the crop tool is open, the preview shows the whole picture around the crop box.
    private(set) var showsCropFrame = false

    func setShowsCropFrame(_ shows: Bool) {
        guard shows != showsCropFrame else { return }
        showsCropFrame = shows
        schedulePreview()
    }

    private var undoStack: [EditRecipe] = []
    private var redoStack: [EditRecipe] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasChanges: Bool { recipe != startRecipe }

    /// Live Photos are saved as copies only; an in-place still edit would drop their motion.
    var canSaveInPlace: Bool { !asset.mediaSubtypes.contains(.photoLive) && asset.canPerform(.content) }

    @ObservationIgnored private var input: PHContentEditingInput?
    @ObservationIgnored private var source: CIImage?
    @ObservationIgnored private var startRecipe = EditRecipe()
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var previewGeneration = 0

    nonisolated static let previewEdge: CGFloat = 1600

    init(asset: PHAsset) {
        self.asset = asset
    }

    // MARK: Loading

    func load() {
        guard phase == .loading, input == nil else { return }
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = false
        options.canHandleAdjustmentData = { @Sendable data in
            data.formatIdentifier == EditRecipe.formatIdentifier && data.formatVersion == EditRecipe.formatVersion
        }
        asset.requestContentEditingInput(with: options) { [weak self] input, info in
            let inCloud = (info[PHContentEditingInputResultIsInCloudKey] as? Bool) == true
            Task { @MainActor in
                self?.finishLoading(input, inCloud: inCloud)
            }
        }
    }

    private func finishLoading(_ input: PHContentEditingInput?, inCloud: Bool) {
        guard let input, let url = input.fullSizeImageURL else {
            phase = .failed(inCloud
                ? "The original is in iCloud and Gallery doesn't download it, so it can't be edited here."
                : "This photo can't be opened for editing.")
            return
        }
        self.input = input
        Task.detached(priority: .userInitiated) { [weak self] in
            let source = Self.previewSource(url)
            await self?.finishSource(source, adjustmentData: input.adjustmentData)
        }
    }

    private func finishSource(_ decoded: CGImage?, adjustmentData: PHAdjustmentData?) {
        guard let decoded else {
            phase = .failed("This photo can't be opened for editing. It may be damaged or in an unsupported format.")
            return
        }
        source = CIImage(cgImage: decoded)
        if let data = adjustmentData,
           let saved = EditRecipe.decode(data.data, formatIdentifier: data.formatIdentifier, formatVersion: data.formatVersion) {
            recipe = saved
            startRecipe = saved
        }
        original = decoded
        phase = .ready
        updateAspect()
        schedulePreview()
    }

    /// A display-sized, upright copy of the original, decoded once.
    nonisolated private static func previewSource(_ url: URL) -> CGImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: previewEdge,
        ]
        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
    }

    // MARK: Editing

    /// Applies a change that ends a gesture: it can be undone.
    func commit(_ change: (inout EditRecipe) -> Void) {
        var next = recipe
        change(&next)
        guard next != recipe else { return }
        undoStack.append(recipe)
        redoStack.removeAll()
        recipe = next
        updateAspect()
        schedulePreview()
    }

    /// Applies a change while a slider or drag is moving. Call `endLiveChange(from:)` when it ends.
    func live(_ change: (inout EditRecipe) -> Void) {
        change(&recipe)
        schedulePreview()
    }

    /// Records the value before a slider or drag started, so the whole gesture undoes at once.
    func endLiveChange(from start: EditRecipe) {
        guard start != recipe else { return }
        undoStack.append(start)
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(recipe)
        recipe = previous
        updateAspect()
        schedulePreview()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(recipe)
        recipe = next
        updateAspect()
        schedulePreview()
    }

    func resetAll() {
        commit { $0 = EditRecipe() }
    }

    private func updateAspect() {
        guard let source else { return }
        let size = source.extent.size
        let turned = recipe.quarterTurns % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
        turnedAspect = turned.height > 0 ? turned.width / turned.height : 1
    }

    // MARK: Preview

    private func schedulePreview() {
        guard let source else { return }
        previewGeneration += 1
        let token = previewGeneration
        let recipe = self.recipe
        let includeCrop = !showsCropFrame
        previewTask?.cancel()
        previewTask = Task.detached(priority: .userInitiated) { [weak self] in
            let rendered = EditRenderer.cgImage(EditRenderer.render(source, recipe, includeCrop: includeCrop))
            guard !Task.isCancelled else { return }
            await self?.finishPreview(rendered, token: token)
        }
    }

    private func finishPreview(_ image: CGImage?, token: Int) {
        guard token == previewGeneration, let image else { return }
        preview = image
    }

    // MARK: Saving

    func save(asCopy: Bool) async -> Bool {
        guard let input, let url = input.fullSizeImageURL, phase == .ready else { return false }
        phase = .saving
        let recipe = self.recipe
        do {
            if asCopy {
                try await saveCopy(from: url, recipe: recipe)
            } else {
                try await saveInPlace(input: input, from: url, recipe: recipe)
            }
            phase = .ready
            startRecipe = recipe
            return true
        } catch let error as PHPhotosError where error.code == .userCancelled {
            phase = .ready
            return false
        } catch {
            phase = .ready
            saveFailed = true
            return false
        }
    }

    /// Set when a save fails, so the screen can say so.
    var saveFailed = false

    private func saveInPlace(input: PHContentEditingInput, from url: URL, recipe: EditRecipe) async throws {
        let output = PHContentEditingOutput(contentEditingInput: input)
        output.adjustmentData = PHAdjustmentData(
            formatIdentifier: EditRecipe.formatIdentifier,
            formatVersion: EditRecipe.formatVersion,
            data: try recipe.encoded()
        )
        let type = output.defaultRenderedContentType ?? .jpeg
        let destination = try output.renderedContentURL(for: type)
        try await Self.renderFull(from: url, recipe: recipe, to: destination, asHEIC: type.conforms(to: .heic))
        let asset = self.asset
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).contentEditingOutput = output
        }
    }

    private func saveCopy(from url: URL, recipe: EditRecipe) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("edit-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(UUID().uuidString + ".heic")
        try await Self.renderFull(from: url, recipe: recipe, to: file, asHEIC: true)
        let date = asset.creationDate
        let location = asset.location
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: file, options: nil)
            request.creationDate = date
            request.location = location
        }
    }

    /// Renders the full-size original off the main thread and writes it to `destination`.
    nonisolated private static func renderFull(from url: URL, recipe: EditRecipe, to destination: URL, asHEIC: Bool) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let rendered = EditRenderer.render(image, recipe)
            try EditRenderer.write(rendered, properties: image.properties, to: destination, asHEIC: asHEIC)
        }.value
    }
}
