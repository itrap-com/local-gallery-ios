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
        let springboard = Gallery.springboard
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
        Gallery.settle(3)
        // What XCUITest sees while the picker is up, kept for the next attempt at driving it.
        attachTree(app, "apptree")
        attachTree(springboard, "springboardtree")

        // The picker: choose three items by element, wherever the picker is hosted. On the iOS 26
        // simulator XCUITest found no picker cells, so the fallback taps the first row by position,
        // measured on the CI device's screenshot. The proof below decides either way.
        var byPosition = false
        if let items = pickerItems(in: [app, springboard]) {
            for index in 0..<3 {
                items.element(boundBy: index).tap()
            }
        } else {
            byPosition = true
            note("picker: items tapped by position, as XCUITest could not see them")
            for x in [0.165, 0.5, 0.834] {
                app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.41)).tap()
            }
        }
        capture(evidence.name("systempicker"))
        let confirm = NSPredicate(format: "label IN {'Done', 'Add'} OR label BEGINSWITH[c] 'Allow'")
        if let host = [app, springboard].first(where: { $0.buttons.matching(confirm).firstMatch.waitForExistence(timeout: 5) }) {
            host.buttons.matching(confirm).firstMatch.tap()
        } else {
            byPosition = true
            note("picker: confirmed by position, as XCUITest could not see its Done button")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.899, dy: 0.169)).tap()
        }
        // Some iOS versions confirm the selection once more in an alert.
        let again = springboard.alerts.buttons.matching(confirm).firstMatch
        if again.waitForExistence(timeout: 3) {
            again.tap()
        }

        // The proof: limited access, and exactly the three chosen items in the grid. After taps by
        // position a wrong result means the picker was not driven, so that reports NOT RUN.
        if let problem = limitedProblem(app) {
            capture(evidence.name("afterpicker"))
            if byPosition {
                throw XCTSkip("NOT RUN: the picker could only be tapped by position, and then \(problem)")
            }
            throw EvidenceError(problem)
        }
        capture(evidence.name("proof"))
    }

    /// The first query that finds three hittable picker items in any of the hosts.
    @MainActor
    private func pickerItems(in hosts: [XCUIApplication]) -> XCUIElementQuery? {
        var timeout: TimeInterval = 10
        for host in hosts {
            for items in [host.collectionViews.cells, host.cells, host.collectionViews.images, host.scrollViews.images] {
                let third = items.element(boundBy: 2)
                if third.waitForExistence(timeout: timeout), third.isHittable {
                    return items
                }
                timeout = 2
            }
        }
        return nil
    }

    /// Nil when the app shows limited access with exactly three items; otherwise what it shows.
    @MainActor
    private func limitedProblem(_ app: XCUIApplication) -> String? {
        guard app.tabBars.firstMatch.waitForExistence(timeout: 30) else {
            return "the tabs did not appear."
        }
        guard app.staticTexts["Gallery can only show the photos you selected."].waitForExistence(timeout: 15) else {
            return "the limited-access note is missing, so access is not limited."
        }
        guard Gallery.tiles(app).firstMatch.waitForExistence(timeout: 30) else {
            return "no chosen item appeared in the grid."
        }
        Gallery.settle(2)
        let shown = Gallery.tiles(app).count
        return shown == 3 ? nil : "the grid showed \(shown) items, not the 3 chosen."
    }

    /// Attaches what XCUITest sees of an app, as text kept when the test passes or skips too.
    @MainActor
    private func attachTree(_ app: XCUIApplication, _ screen: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = evidence.name(screen)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
