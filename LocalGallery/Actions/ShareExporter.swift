import AVFoundation
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// Files prepared for the share sheet. They live in a private temporary folder that is removed
/// when sharing ends.
struct ShareBatch: Identifiable {
    let id = UUID()
    let folder: URL
    let files: [URL]
    /// Items that could not be prepared, e.g. originals that are only in iCloud.
    let skipped: Int

    func discard() {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Copies originals out of the photo library for sharing.
///
/// Files get random names, never the original filename. Nothing is downloaded from iCloud. With
/// `removeLocation`, photos are copied without GPS metadata (the image data itself is not
/// re-encoded) and videos are re-wrapped without location metadata.
enum ShareExporter {
    private static let folderPrefix = "share-"

    static func export(_ assets: [PHAsset], removeLocation: Bool) async -> ShareBatch? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(folderPrefix + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        var files: [URL] = []
        var skipped = 0
        for asset in assets {
            if Task.isCancelled { break }
            if let file = await exportOne(asset, into: folder, removeLocation: removeLocation) {
                files.append(file)
            } else {
                skipped += 1
            }
        }
        guard !files.isEmpty else {
            try? FileManager.default.removeItem(at: folder)
            return ShareBatch(folder: folder, files: [], skipped: skipped)
        }
        return ShareBatch(folder: folder, files: files, skipped: skipped)
    }

    /// Removes share folders left behind if Gallery quit while sharing.
    static func removeLeftovers() {
        let temp = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []
        for name in names where name.hasPrefix(folderPrefix) {
            try? FileManager.default.removeItem(at: temp.appendingPathComponent(name, isDirectory: true))
        }
    }

    private static func exportOne(_ asset: PHAsset, into folder: URL, removeLocation: Bool) async -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred: [PHAssetResourceType] = asset.mediaType == .video
            ? [.fullSizeVideo, .video]
            : [.fullSizePhoto, .photo]
        guard let resource = preferred.lazy.compactMap({ type in resources.first { $0.type == type } }).first
        else { return nil }

        let type = UTType(resource.uniformTypeIdentifier)
        let ext = type?.preferredFilenameExtension ?? (asset.mediaType == .video ? "mov" : "jpg")
        let original = folder.appendingPathComponent("\(UUID().uuidString).\(ext)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: original, options: options)
        } catch {
            return nil
        }
        guard removeLocation else { return original }

        let cleaned = folder.appendingPathComponent("\(UUID().uuidString).\(ext)")
        let ok = asset.mediaType == .video
            ? await copyVideoWithoutLocation(from: original, to: cleaned, ext: ext)
            : copyImageWithoutLocation(from: original, to: cleaned, type: type)
        try? FileManager.default.removeItem(at: original)
        return ok ? cleaned : nil
    }

    /// Copies the image with its GPS metadata excluded. The compressed image data is copied as is.
    private static func copyImageWithoutLocation(from source: URL, to destination: URL, type: UTType?) -> Bool {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let sourceType = CGImageSourceGetType(imageSource) ?? (type?.identifier as CFString?),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, sourceType, 1, nil)
        else { return false }
        let options: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true]
        return CGImageDestinationCopyImageSource(output, imageSource, options as CFDictionary, nil)
    }

    /// Re-wraps the video without re-encoding, dropping location and other identifying metadata.
    private static func copyVideoWithoutLocation(from source: URL, to destination: URL, ext: String) async -> Bool {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        else { return false }
        session.metadataItemFilter = .forSharing()
        let fileType: AVFileType = ext.lowercased() == "mp4" ? .mp4 : .mov
        do {
            try await session.export(to: destination, as: fileType)
            return true
        } catch {
            return false
        }
    }
}
