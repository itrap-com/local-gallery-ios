import Foundation
import XCTest
@testable import GalleryCore

final class EditRecipeTests: XCTestCase {
    private func assertRect(_ a: NormRect, _ b: NormRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: 1e-9, file: file, line: line)
    }

    func testNewRecipeIsIdentity() {
        XCTAssertTrue(EditRecipe().isIdentity)
        XCTAssertFalse(EditRecipe().hasGeometry)
    }

    func testAdjustmentsClampAndDropZero() {
        var recipe = EditRecipe()
        recipe[.exposure] = 3
        XCTAssertEqual(recipe[.exposure], 1)
        recipe[.vignette] = -0.5
        XCTAssertEqual(recipe[.vignette], 0)
        XCTAssertNil(recipe.adjustments["vignette"])
        recipe[.exposure] = 0
        XCTAssertTrue(recipe.isIdentity)
    }

    func testFourTurnsRestoreTheCrop() {
        var recipe = EditRecipe()
        recipe.crop = NormRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        for _ in 0..<4 { recipe.rotateClockwise() }
        XCTAssertEqual(recipe.quarterTurns, 0)
        assertRect(recipe.crop, NormRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    }

    func testClockwiseTurnMovesTopLeftToTopRight() {
        let turned = EditGeometry.rotatedClockwise(NormRect(x: 0, y: 0, width: 0.5, height: 0.25))
        assertRect(turned, NormRect(x: 0.75, y: 0, width: 0.25, height: 0.5))
    }

    func testClockwiseTurnOnAFlippedPictureIsStoredAsThree() {
        var recipe = EditRecipe()
        recipe.flipHorizontally()
        recipe.rotateClockwise()
        XCTAssertEqual(recipe.quarterTurns, 3)
        recipe.rotateClockwise()
        XCTAssertEqual(recipe.quarterTurns, 2)
    }

    func testFlipMirrorsTheStraightenAngle() {
        var recipe = EditRecipe()
        recipe.straighten = 7
        recipe.flipHorizontally()
        XCTAssertEqual(recipe.straighten, -7)
        recipe.flipHorizontally()
        XCTAssertEqual(recipe.straighten, 7)
    }

    func testFlipMirrorsTheCrop() {
        let flipped = EditGeometry.flippedHorizontally(NormRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        assertRect(flipped, NormRect(x: 0.6, y: 0.2, width: 0.3, height: 0.4))
    }

    func testStraightenScale() {
        XCTAssertEqual(EditGeometry.straightenScale(width: 4, height: 3, degrees: 0), 1, accuracy: 1e-12)
        // A square turned 45° must grow by √2 to keep filling its frame.
        XCTAssertEqual(EditGeometry.straightenScale(width: 1, height: 1, degrees: 45), 2.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(
            EditGeometry.straightenScale(width: 4, height: 3, degrees: -10),
            EditGeometry.straightenScale(width: 4, height: 3, degrees: 10),
            accuracy: 1e-12
        )
    }

    func testCenteredSquareCropInLandscape() {
        assertRect(EditGeometry.centeredCrop(aspect: 1, imageAspect: 2), NormRect(x: 0.25, y: 0, width: 0.5, height: 1))
    }

    func testCenteredWideCropInSquare() {
        assertRect(EditGeometry.centeredCrop(aspect: 2, imageAspect: 1), NormRect(x: 0, y: 0.25, width: 1, height: 0.5))
    }

    func testMoveStaysInside() {
        let moved = EditGeometry.move(NormRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4), dx: 0.5, dy: -1)
        assertRect(moved, NormRect(x: 0.6, y: 0, width: 0.4, height: 0.4))
    }

    func testFreeResizeKeepsOppositeCorner() {
        let rect = EditGeometry.resize(.full, corner: .topLeft, dx: 0.2, dy: 0.1, ratio: nil)
        assertRect(rect, NormRect(x: 0.2, y: 0.1, width: 0.8, height: 0.9))
    }

    func testResizeStopsAtTheEdgeAndMinimum() {
        let start = NormRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let grown = EditGeometry.resize(start, corner: .bottomRight, dx: 2, dy: 2, ratio: nil)
        assertRect(grown, NormRect(x: 0.2, y: 0.2, width: 0.8, height: 0.8))
        let shrunk = EditGeometry.resize(start, corner: .bottomRight, dx: -2, dy: -2, ratio: nil)
        assertRect(shrunk, NormRect(x: 0.2, y: 0.2, width: EditGeometry.minimumSide, height: EditGeometry.minimumSide))
    }

    func testLockedRatioHolds() {
        let rect = EditGeometry.resize(.full, corner: .bottomRight, dx: -0.5, dy: -0.1, ratio: 1)
        XCTAssertEqual(rect.width / rect.height, 1, accuracy: 1e-9)
        XCTAssertEqual(rect.x, 0, accuracy: 1e-9)
        XCTAssertEqual(rect.y, 0, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(rect.x + rect.width, 1 + 1e-9)
    }

    func testPixelRectFlipsToBottomLeftOrigin() {
        let r = EditGeometry.pixelRect(NormRect(x: 0.25, y: 0, width: 0.5, height: 0.5), width: 400, height: 200)
        XCTAssertEqual(r.x, 100)
        XCTAssertEqual(r.y, 100)
        XCTAssertEqual(r.width, 200)
        XCTAssertEqual(r.height, 100)
    }

    func testRoundTripAndVersionGate() throws {
        var recipe = EditRecipe()
        recipe[.contrast] = 0.4
        recipe.filter = .noir
        recipe.rotateClockwise()
        let data = try recipe.encoded()
        XCTAssertEqual(
            EditRecipe.decode(data, formatIdentifier: EditRecipe.formatIdentifier, formatVersion: "1"),
            recipe
        )
        XCTAssertNil(EditRecipe.decode(data, formatIdentifier: EditRecipe.formatIdentifier, formatVersion: "2"))
        XCTAssertNil(EditRecipe.decode(data, formatIdentifier: "com.example.other", formatVersion: "1"))
    }
}
