import XCTest

/// EXPERIMENTAL. Grants limited photo access the way a person does, through the system dialog and
/// picker, then proves it: the Library grid must show exactly the three chosen items. When the
/// system UI can't be driven, the test skips with the reason and the workflow reports NOT RUN; it
/// never fakes the state.
final class LimitedAccessTests: XCTestCase {
    private var evidence: Evidence!

    override func setUpWithError() throws {
        continueAfterFailure = false
        evidence = try Evidence.current()
        guard evidence.access == .limited else {
            throw XCTSkip("Runs only in the evidence workflow's limited-access job.")
        }
    }

    @MainActor
    func testChooseThreeItemsInTheSystemPicker() throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()
        let start = app.buttons["Continue"]
        try require(start.waitForExistence(timeout: 30),
                    "The first-run explanation screen did not appear, so photo access was not reset.")
        start.tap()

        // The system access dialog: choose limited access.
        let limit = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Limit'")).firstMatch
        guard limit.waitForExistence(timeout: 20) else {
            capture(evidence.name("systemdialog"))
            throw XCTSkip("NOT RUN: the system photo-access dialog showed no Limit Access button.")
        }
        capture(evidence.name("systemdialog"))
        limit.tap()

        // The system picker: choose its first three items, wherever the picker is hosted.
        let hosts = [app, springboard]
        guard let picker = hosts.first(where: { $0.collectionViews.cells.element(boundBy: 2).waitForExistence(timeout: 10) }) else {
            capture(evidence.name("systempicker"))
            throw XCTSkip("NOT RUN: the system picker's items could not be found.")
        }
        for index in 0..<3 {
            picker.collectionViews.cells.element(boundBy: index).tap()
        }
        capture(evidence.name("systempicker"))
        let confirm = NSPredicate(format: "label IN {'Done', 'Continue', 'Add'} OR label BEGINSWITH[c] 'Allow'")
        guard let host = [picker, springboard].first(where: { $0.buttons.matching(confirm).firstMatch.waitForExistence(timeout: 5) }) else {
            throw XCTSkip("NOT RUN: the system picker showed no button to confirm the selection.")
        }
        host.buttons.matching(confirm).firstMatch.tap()
        // Some iOS versions confirm the selection once more in an alert.
        let again = springboard.alerts.buttons.matching(confirm).firstMatch
        if again.waitForExistence(timeout: 3) {
            again.tap()
        }

        // The proof: limited access, and exactly the three chosen items in the grid.
        try require(app.tabBars.firstMatch.waitForExistence(timeout: 30), "The tabs did not appear after access was granted.")
        try require(app.staticTexts["Gallery can only show the photos you selected."].waitForExistence(timeout: 15),
                    "The limited-access note is missing, so access is not limited.")
        try require(Gallery.tiles(app).firstMatch.waitForExistence(timeout: 30), "No chosen item appeared in the grid.")
        Gallery.settle(2)
        XCTAssertEqual(Gallery.tiles(app).count, 3, "The grid must show exactly the three chosen items.")
        capture(evidence.name("proof"))
    }
}
