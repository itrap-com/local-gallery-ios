import os
import XCTest

/// Launch, scroll and viewer timings on the seeded full-access library: 10,000 pictures, or 2,000
/// when seeding ran past its budget (the job summary says which). Five iterations each.
final class PerformanceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard try Evidence.current().access == .full else {
            throw XCTSkip("Performance runs only on the seeded full-access library.")
        }
    }

    @MainActor
    func testColdLaunch() throws {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: Self.options()) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testGridFling() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(Gallery.tiles(app).firstMatch.waitForExistence(timeout: 90), "The seeded library did not appear.")
        let grid = app.scrollViews.firstMatch
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: Self.options(manualStop: true)) {
            grid.swipeUp(velocity: .fast)
            stopMeasuring()
            grid.swipeDown(velocity: .fast)
        }
    }

    @MainActor
    func testViewerOpen() throws {
        let app = XCUIApplication()
        app.launch()
        let tile = Gallery.tiles(app).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 90), "The seeded library did not appear.")
        let close = app.buttons["Close"]
        let metrics: [XCTMetric] = [ViewerSignpost.metric, XCTClockMetric()]
        measure(metrics: metrics, options: Self.options(manualStop: true)) {
            let interval = ViewerSignpost.signposter.beginInterval(ViewerSignpost.name)
            tile.tap()
            let opened = close.waitForExistence(timeout: 15)
            ViewerSignpost.signposter.endInterval(ViewerSignpost.name, interval)
            stopMeasuring()
            XCTAssertTrue(opened, "The viewer did not open.")
            close.tap()
            _ = tile.waitForExistence(timeout: 15)
        }
    }

    private static func options(manualStop: Bool = false) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        if manualStop {
            options.invocationOptions = [.manuallyStop]
        }
        return options
    }
}

/// The viewer-open interval, emitted by the test runner from tap to the viewer's Close button. Its
/// name is a static string: no item, file or album ever goes into a signpost.
private enum ViewerSignpost {
    static let subsystem = "Local-gallery.ios.uitests"
    static let category = "Evidence"
    static let name: StaticString = "ViewerOpen"
    static let signposter = OSSignposter(subsystem: subsystem, category: category)
    static var metric: XCTMetric {
        XCTOSSignpostMetric(subsystem: subsystem, category: category, name: "ViewerOpen")
    }
}
