import GalleryCore
import Photos
import SwiftUI

/// The photo editor: Adjust, Filters and Crop, with undo, redo and press-and-hold to compare.
struct EditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditorModel
    @State private var tool: Tool = .adjust
    @State private var adjustment: Adjustment = .exposure
    @State private var liveStart: EditRecipe?
    @State private var comparing = false
    @State private var confirmDiscard = false
    @State private var aspect: CropAspect = .free

    enum Tool: String, CaseIterable, Identifiable {
        case adjust = "Adjust"
        case filters = "Filters"
        case crop = "Crop"
        var id: String { rawValue }
    }

    init(asset: PHAsset) {
        _model = State(initialValue: EditorModel(asset: asset))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.phase == .ready || model.phase == .saving {
                toolPanel
                    .frame(height: 150)
                Picker("Tool", selection: $tool) {
                    ForEach(Tool.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { model.load() }
        .onChange(of: tool) { _, next in model.setShowsCropFrame(next == .crop) }
        .confirmationDialog("Discard your edits?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Edits", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .alert("Couldn't save", isPresented: Binding(get: { model.saveFailed }, set: { model.saveFailed = $0 })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Gallery couldn't save this edit. The original photo is unchanged.")
        }
        .overlay {
            if model.phase == .saving {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("Saving")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 18) {
            Button("Cancel") {
                if model.hasChanges {
                    confirmDiscard = true
                } else {
                    dismiss()
                }
            }
            Spacer()
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .accessibilityLabel("Undo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
                .accessibilityLabel("Redo")
            Button {
                model.commit { $0.autoEnhance.toggle() }
            } label: {
                Image(systemName: model.recipe.autoEnhance ? "wand.and.stars.inverse" : "wand.and.stars")
            }
            .accessibilityLabel(model.recipe.autoEnhance ? "Turn off auto-enhance" : "Auto-enhance")
            Spacer()
            Menu {
                if model.canSaveInPlace {
                    Button("Save") { save(asCopy: false) }
                }
                Button("Save as Copy") { save(asCopy: true) }
                if !model.canSaveInPlace {
                    Text("Live Photos are saved as a new still photo; the original stays as it is.")
                }
            } label: {
                Text("Done").fontWeight(.semibold)
            }
            .disabled(!model.hasChanges || model.phase != .ready)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .disabled(model.phase == .saving)
    }

    private func save(asCopy: Bool) {
        Task {
            if await model.save(asCopy: asCopy) {
                dismiss()
            }
        }
    }

    // MARK: Canvas

    @ViewBuilder
    private var canvas: some View {
        switch model.phase {
        case .failed(let text):
            UnavailableMediaNotice(symbol: "exclamationmark.triangle", text: text)
        case .loading:
            ProgressView()
                .tint(.white)
        case .ready, .saving:
            GeometryReader { proxy in
                let image = comparing ? model.original : model.preview
                ZStack {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if tool == .crop, !comparing, let preview = model.preview {
                        CropOverlay(
                            model: model,
                            fitted: Self.fittedRect(
                                image: CGSize(width: preview.width, height: preview.height),
                                in: proxy.size
                            ),
                            ratio: aspect.normalizedRatio(imageAspect: model.turnedAspect)
                        )
                    }
                }
                .contentShape(Rectangle())
                // Holding a finger on the photo shows the original; the crop tool's own drags win.
                .onLongPressGesture(minimumDuration: 600, maximumDistance: 40, perform: {}, onPressingChanged: { pressing in
                    comparing = pressing && tool != .crop
                })
                .accessibilityElement(children: tool == .crop ? .contain : .ignore)
                .accessibilityLabel(comparing ? "Original photo" : "Edited photo")
            }
            .padding(tool == .crop ? 20 : 0)
            .padding(.vertical, 8)
        }
    }

    static func fittedRect(image: CGSize, in container: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = min(container.width / image.width, container.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: Tools

    @ViewBuilder
    private var toolPanel: some View {
        switch tool {
        case .adjust: adjustPanel
        case .filters: filterPanel
        case .crop: cropPanel
        }
    }

    private var adjustPanel: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Adjustment.allCases, id: \.self) { item in
                        Button {
                            adjustment = item
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: Self.symbol(for: item))
                                    .font(.title3)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        Circle().fill(item == adjustment ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if model.recipe[item] != 0 {
                                            Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                                        }
                                    }
                                Text(item.title)
                                    .font(.caption2)
                            }
                            .foregroundStyle(.white)
                        }
                        .accessibilityLabel(item.title)
                        .accessibilityValue(Self.percent(model.recipe[item]))
                        .accessibilityAddTraits(item == adjustment ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            sliderRow(
                title: adjustment.title,
                value: model.recipe[adjustment],
                range: adjustment.range,
                reset: { model.commit { $0[adjustment] = 0 } }
            ) { value in
                let item = adjustment
                model.live { $0[item] = value }
            }
        }
    }

    private var filterPanel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                filterChip(nil, title: "Original")
                ForEach(FilterPreset.allCases, id: \.self) { preset in
                    filterChip(preset, title: preset.title)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(_ preset: FilterPreset?, title: String) -> some View {
        let selected = model.recipe.filter == preset
        return Button {
            model.commit { $0.filter = preset }
        } label: {
            VStack(spacing: 6) {
                FilterThumbnail(source: model.original, preset: preset)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.white : .clear, lineWidth: 2))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var cropPanel: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(CropAspect.allCases) { option in
                        Button(option.title) {
                            aspect = option
                            if let ratio = option.ratio(turnedAspect: model.turnedAspect) {
                                model.commit {
                                    $0.crop = EditGeometry.centeredCrop(aspect: ratio, imageAspect: model.turnedAspect)
                                }
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(aspect == option ? Color.white.opacity(0.25) : Color.white.opacity(0.08)))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(aspect == option ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 24) {
                Button {
                    // A locked shape would snap the turned box back; start free after a turn.
                    aspect = .free
                    model.commit { $0.rotateClockwise() }
                } label: {
                    Image(systemName: "rotate.right")
                }
                .accessibilityLabel("Rotate 90 degrees")
                Button { model.commit { $0.flipHorizontally() } } label: {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                .accessibilityLabel("Flip")
                Button("Reset") {
                    aspect = .free
                    model.commit {
                        $0.quarterTurns = 0
                        $0.flipped = false
                        $0.straighten = 0
                        $0.crop = .full
                    }
                }
                .disabled(!model.recipe.hasGeometry)
            }
            .font(.title3)
            .foregroundStyle(.white)
            sliderRow(
                title: "Straighten",
                value: model.recipe.straighten / 45,
                range: -1...1,
                reset: { model.commit { $0.straighten = 0 } }
            ) { value in
                model.live { $0.straighten = value * 45 }
            }
        }
    }

    private func sliderRow(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        reset: @escaping () -> Void,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(Self.percent(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 44, alignment: .trailing)
            Slider(
                value: Binding(get: { value }, set: { next in
                    // VoiceOver adjusts without an editing phase; make each such step undoable.
                    if liveStart == nil {
                        let start = model.recipe
                        onChange(next)
                        model.endLiveChange(from: start)
                    } else {
                        onChange(next)
                    }
                }),
                in: range,
                onEditingChanged: { editing in
                    if editing {
                        liveStart = model.recipe
                    } else if let start = liveStart {
                        model.endLiveChange(from: start)
                        liveStart = nil
                    }
                }
            )
            .accessibilityLabel(title)
            .accessibilityValue(Self.percent(value))
            Button("Reset", action: reset)
                .font(.caption)
                .foregroundStyle(.white)
                .disabled(value == 0)
        }
        .padding(.horizontal, 16)
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))"
    }

    private static func symbol(for adjustment: Adjustment) -> String {
        switch adjustment {
        case .exposure: "plusminus.circle"
        case .brightness: "sun.max"
        case .contrast: "circle.lefthalf.filled"
        case .highlights: "circle.righthalf.filled"
        case .shadows: "shadow"
        case .saturation: "drop"
        case .vibrance: "drop.halffull"
        case .warmth: "thermometer.medium"
        case .tint: "eyedropper"
        case .sharpness: "triangle"
        case .vignette: "circle.dashed"
        }
    }
}

/// Crop shapes. The ratio is width:height in the picture as currently turned.
enum CropAspect: String, CaseIterable, Identifiable {
    case free, original, square, fourThree, threeFour, sixteenNine, nineSixteen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "Free"
        case .original: "Original"
        case .square: "Square"
        case .fourThree: "4:3"
        case .threeFour: "3:4"
        case .sixteenNine: "16:9"
        case .nineSixteen: "9:16"
        }
    }

    /// The width:height ratio in pixels; Original means the picture's own shape as turned.
    func ratio(turnedAspect: Double) -> Double? {
        switch self {
        case .free: nil
        case .original: turnedAspect > 0 ? turnedAspect : nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .threeFour: 3.0 / 4.0
        case .sixteenNine: 16.0 / 9.0
        case .nineSixteen: 9.0 / 16.0
        }
    }

    /// The locked ratio in normalized crop units, or nil for a free crop.
    func normalizedRatio(imageAspect: Double) -> Double? {
        guard self != .free, imageAspect > 0 else { return nil }
        let value: Double
        switch self {
        case .original: return 1
        case .square: value = 1
        case .fourThree: value = 4.0 / 3.0
        case .threeFour: value = 3.0 / 4.0
        case .sixteenNine: value = 16.0 / 9.0
        case .nineSixteen: value = 9.0 / 16.0
        case .free: return nil
        }
        return value / imageAspect
    }
}

/// A small preview of one filter, rendered off the main thread from the editor's source.
private struct FilterThumbnail: View {
    let source: CGImage?
    let preset: FilterPreset?
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: preset) {
            guard let source, image == nil else { return }
            let preset = self.preset
            image = await Task.detached(priority: .utility) {
                let input = CIImage(cgImage: source)
                let scale = 160 / max(input.extent.width, input.extent.height)
                var recipe = EditRecipe()
                recipe.filter = preset
                let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                return EditRenderer.cgImage(EditRenderer.color(small, recipe))
            }.value
        }
    }
}
