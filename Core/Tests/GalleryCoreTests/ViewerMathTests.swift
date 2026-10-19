import XCTest
@testable import GalleryCore

final class ViewerMathTests: XCTestCase {
    func testSmallImageIsRequestedAtItsOwnSize() {
        let size = PixelSize(width: 1200, height: 900)
        XCTAssertEqual(ViewerMath.decodeSize(for: size), size)
    }

    func testLongEdgeIsCappedKeepingAspectRatio() {
        let decoded = ViewerMath.decodeSize(for: PixelSize(width: 16000, height: 4000))
        XCTAssertEqual(decoded, PixelSize(width: 4096, height: 1024))
    }

    func testPortraitPanoramaIsCappedOnHeight() {
        let decoded = ViewerMath.decodeSize(for: PixelSize(width: 3000, height: 12000))
        XCTAssertEqual(decoded, PixelSize(width: 1024, height: 4096))
    }

    func testExtremeAspectRatioNeverRoundsToZero() {
        let decoded = ViewerMath.decodeSize(for: PixelSize(width: 100_000, height: 2))
        XCTAssertEqual(decoded, PixelSize(width: 4096, height: 1))
    }

    func testUnknownDimensionsGiveNoDecodeSize() {
        XCTAssertNil(ViewerMath.decodeSize(for: PixelSize(width: 0, height: 0)))
        XCTAssertNil(ViewerMath.decodeSize(for: PixelSize(width: 4000, height: -1)))
    }

    func testDimensionsTextHidesUnknownSizes() {
        XCTAssertEqual(ViewerMath.dimensionsText(PixelSize(width: 4032, height: 3024)), "4032 × 3024")
        XCTAssertNil(ViewerMath.dimensionsText(PixelSize(width: 0, height: 3024)))
    }

    func testCoordinateTextUsesHemispheres() {
        XCTAssertEqual(
            ViewerMath.coordinateText(latitude: 37.331821, longitude: -122.031181),
            "37.33182° N, 122.03118° W"
        )
        XCTAssertEqual(
            ViewerMath.coordinateText(latitude: -33.8568, longitude: 151.2153),
            "33.85680° S, 151.21530° E"
        )
    }

    func testCoordinateTextRejectsInvalidValues() {
        XCTAssertNil(ViewerMath.coordinateText(latitude: 91, longitude: 0))
        XCTAssertNil(ViewerMath.coordinateText(latitude: 0, longitude: -180.5))
        XCTAssertNil(ViewerMath.coordinateText(latitude: .nan, longitude: 0))
    }

    func testNeighborsStayInsideTheLibrary() {
        XCTAssertEqual(ViewerMath.neighbors(of: 0, count: 10), [1, 2])
        XCTAssertEqual(ViewerMath.neighbors(of: 5, count: 10), [3, 4, 6, 7])
        XCTAssertEqual(ViewerMath.neighbors(of: 9, count: 10), [7, 8])
        XCTAssertEqual(ViewerMath.neighbors(of: 0, count: 1), [])
        XCTAssertEqual(ViewerMath.neighbors(of: 3, count: 2), [])
    }

    func testDismissProgressIsClamped() {
        XCTAssertEqual(ViewerMath.dismissProgress(translation: -40, viewHeight: 800), 0)
        XCTAssertEqual(ViewerMath.dismissProgress(translation: 160, viewHeight: 800), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ViewerMath.dismissProgress(translation: 2000, viewHeight: 800), 1)
    }

    func testDismissNeedsDistanceOrSpeed() {
        XCTAssertFalse(ViewerMath.shouldDismiss(translation: 50, velocity: 100, viewHeight: 800))
        XCTAssertTrue(ViewerMath.shouldDismiss(translation: 200, velocity: 0, viewHeight: 800))
        XCTAssertTrue(ViewerMath.shouldDismiss(translation: 30, velocity: 1500, viewHeight: 800))
        XCTAssertFalse(ViewerMath.shouldDismiss(translation: -200, velocity: 1500, viewHeight: 800))
    }
}
