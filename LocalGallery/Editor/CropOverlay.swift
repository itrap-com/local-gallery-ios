import GalleryCore
import SwiftUI

/// The crop box over the whole picture: drag a corner to resize, drag inside to move. The area
/// outside the box is dimmed. All math is in `EditGeometry`, shared with the export.
struct CropOverlay: View {
    let model: EditorModel
    /// Where the picture is drawn, in this view's coordinates.
    let fitted: CGRect
    /// The locked ratio in normalized units, or nil for a free crop.
    let ratio: Double?

    @State private var dragStart: NormRect?
    @State private var startRecipe: EditRecipe?
    /// Resets by itself when SwiftUI cancels a drag, which `onEnded` never reports.
    @GestureState private var dragging = false

    private var box: CGRect {
        let crop = model.recipe.crop
        return CGRect(
            x: fitted.minX + crop.x * fitted.width,
            y: fitted.minY + crop.y * fitted.height,
            width: crop.width * fitted.width,
            height: crop.height * fitted.height
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(fitted)
                path.addRect(box)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: box.width, height: box.height)
                .overlay { thirdsGrid }
                .contentShape(Rectangle())
                .offset(x: box.minX, y: box.minY)
                .gesture(moveGesture)
                .accessibilityLabel("Crop area")
                .accessibilityHint("Drag to move")

            ForEach(CropCorner.allCases, id: \.self) { corner in
                handle
                    .position(point(for: corner))
                    .gesture(resizeGesture(corner))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: dragging) { _, active in
            if !active {
                end()
            }
        }
    }

    private var thirdsGrid: some View {
        GeometryReader { proxy in
            Path { path in
                for i in 1...2 {
                    let x = proxy.size.width * CGFloat(i) / 3
                    let y = proxy.size.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    private var handle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 18, height: 18)
            .padding(13)
            .contentShape(Circle())
    }

    private func point(for corner: CropCorner) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: box.minX, y: box.minY)
        case .topRight: CGPoint(x: box.maxX, y: box.minY)
        case .bottomLeft: CGPoint(x: box.minX, y: box.maxY)
        case .bottomRight: CGPoint(x: box.maxX, y: box.maxY)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                let start = begin()
                let dx = value.translation.width / max(fitted.width, 1)
                let dy = value.translation.height / max(fitted.height, 1)
                model.live { $0.crop = EditGeometry.move(start, dx: dx, dy: dy) }
            }
    }

    private func resizeGesture(_ corner: CropCorner) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                let start = begin()
                let dx = value.translation.width / max(fitted.width, 1)
                let dy = value.translation.height / max(fitted.height, 1)
                let ratio = self.ratio
                model.live { $0.crop = EditGeometry.resize(start, corner: corner, dx: dx, dy: dy, ratio: ratio) }
            }
    }

    private func begin() -> NormRect {
        if let dragStart {
            return dragStart
        }
        dragStart = model.recipe.crop
        startRecipe = model.recipe
        return model.recipe.crop
    }

    private func end() {
        if let startRecipe {
            model.endLiveChange(from: startRecipe)
        }
        dragStart = nil
        startRecipe = nil
    }
}
