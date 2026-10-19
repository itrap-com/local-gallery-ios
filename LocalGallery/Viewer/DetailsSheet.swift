import CoreLocation
import GalleryCore
import Photos
import SwiftUI
import UniformTypeIdentifiers

/// What Gallery can say about one item, read from PhotoKit on this iPhone.
///
/// Location stays hidden until the owner asks for it, and then shows as coordinates only: nothing
/// is looked up, so no place name is resolved and nothing leaves the device.
struct DetailsSheet: View {
    let asset: PHAsset

    @Environment(\.dismiss) private var dismiss
    @State private var showsLocation = false
    @State private var formatName: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Type", kindText)
                    if let format = formatName {
                        row("Format", format)
                    }
                    if let dimensions = ViewerMath.dimensionsText(
                        PixelSize(width: asset.pixelWidth, height: asset.pixelHeight)
                    ) {
                        row("Dimensions", dimensions)
                    }
                    if asset.mediaType == .video {
                        row("Length", Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))
                    }
                }
                Section {
                    row("Taken", dateText(asset.creationDate))
                    row("Modified", dateText(asset.modificationDate))
                }
                locationSection
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: asset.localIdentifier) {
            formatName = Self.formatName(for: asset)
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        Section {
            if let location = asset.location {
                if showsLocation {
                    row(
                        "Coordinates",
                        ViewerMath.coordinateText(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        ) ?? "Not readable"
                    )
                } else {
                    Button("Show location") { showsLocation = true }
                }
            } else {
                Text("No location saved with this item")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Location")
        } footer: {
            Text("Read from the item itself. Gallery never looks places up or sends anything anywhere.")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }

    private var kindText: String {
        let subtypes = asset.mediaSubtypes
        if asset.mediaType == .video {
            if subtypes.contains(.videoHighFrameRate) { return "Slow-motion video" }
            if subtypes.contains(.videoTimelapse) { return "Time-lapse video" }
            return "Video"
        }
        if subtypes.contains(.photoScreenshot) { return "Screenshot" }
        if subtypes.contains(.photoPanorama) { return "Panorama" }
        if subtypes.contains(.photoLive) { return "Live Photo" }
        if subtypes.contains(.photoHDR) { return "HDR photo" }
        return "Photo"
    }

    private func dateText(_ date: Date?) -> String {
        date?.formatted(date: .long, time: .shortened) ?? "Unknown"
    }

    /// The original's file type, e.g. "HEIF Image". Uses only the type identifier, never the name.
    private static func formatName(for asset: PHAsset) -> String? {
        let primary: [PHAssetResourceType] = asset.mediaType == .video ? [.video] : [.photo]
        let resource = PHAssetResource.assetResources(for: asset).first { primary.contains($0.type) }
        guard let identifier = resource?.uniformTypeIdentifier,
              let type = UTType(identifier)
        else { return nil }
        return type.localizedDescription
    }
}
