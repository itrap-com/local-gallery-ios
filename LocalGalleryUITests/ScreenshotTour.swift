import XCTest

/// Captures every screen the app shows in the photo-access state the workflow set up: the access
/// screens, each tab and the viewer, plus the editor and Hidden screens when the build has them.
/// Each screenshot is named <screen>-<access>-<appearance>-<textsize> and kept with the result.
final class ScreenshotTour: XCTestCase {
    private var evidence: Evidence!

    override func setUpWithError() throws {
        continueAfterFailure = false
        evidence = try Evidence.current()
    }

    @MainActor
    func testTour() throws {
        let app = XCUIApplication()
        app.launch()
        switch evidence.access {
        case .notdetermined:
            try require(app.buttons["Continue"].waitForExistence(timeout: 30),
                        "The first-run explanation screen did not appear.")
            capture(evidence.name("access"))
        case .denied:
            try require(app.buttons["Open Settings"].waitForExistence(timeout: 30),
                        "The access-denied screen did not appear.")
            try require(!app.tabBars.firstMatch.exists, "Tabs are showing although photo access should be denied.")
            capture(evidence.name("access"))
        case .empty:
            try allowFullAccessIfAsked(app, evidence)
            try require(app.tabBars.firstMatch.waitForExistence(timeout: 30), "The tabs did not appear.")
            let emptyNote = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'has no photos yet'")).firstMatch
            guard emptyNote.waitForExistence(timeout: 30) else {
                let visible = Gallery.tiles(app).count
                throw EvidenceError("The library is not empty (\(visible) items visible), so the empty state was not set up.")
            }
            capture(evidence.name("library"))
            note("viewer: nothing to open in an empty library")
            try tourAlbumsAndSearch(app)
        case .full, .limited:
            if evidence.access == .full {
                try allowFullAccessIfAsked(app, evidence)
            }
            try require(app.tabBars.firstMatch.waitForExistence(timeout: 30), "The tabs did not appear.")
            try require(Gallery.tiles(app).firstMatch.waitForExistence(timeout: 90),
                        "No photo or video appeared in the Library grid.")
            if evidence.access == .limited {
                try require(app.staticTexts["Gallery can only show the photos you selected."].exists,
                            "The limited-access note is missing, so access is not limited.")
            }
            capture(evidence.name("library"))
            try tourViewer(app)
            try tourAlbumsAndSearch(app)
        }
    }

    @MainActor
    private func tourViewer(_ app: XCUIApplication) throws {
        Gallery.tiles(app).firstMatch.tap()
        let close = app.buttons["Close"]
        try require(close.waitForExistence(timeout: 15), "The viewer did not open.")
        capture(evidence.name("viewer"))
        let edit = app.buttons["Edit"]
        if edit.waitForExistence(timeout: 2) {
            edit.tap()
            let cancel = app.buttons["Cancel"]
            try require(cancel.waitForExistence(timeout: 15), "The editor did not open.")
            capture(evidence.name("editor"))
            cancel.tap()
            let discard = app.buttons["Discard Edits"]
            if discard.waitForExistence(timeout: 2) {
                discard.tap()
            }
            try require(close.waitForExistence(timeout: 15), "The viewer did not come back from the editor.")
        } else {
            note("editor: not in this build")
        }
        close.tap()
        try require(app.tabBars.firstMatch.waitForExistence(timeout: 15), "The viewer did not close.")
    }

    @MainActor
    private func tourAlbumsAndSearch(_ app: XCUIApplication) throws {
        Gallery.tab(app, "Albums").tap()
        try require(app.navigationBars["Albums"].waitForExistence(timeout: 15), "The Albums tab did not open.")
        capture(evidence.name("albums"))
        let hidden = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Hidden from Gallery views'")).firstMatch
        if hidden.waitForExistence(timeout: 2) {
            hidden.tap()
            let bar = app.navigationBars["Hidden"]
            if bar.waitForExistence(timeout: 15) {
                if try passHiddenPrompt(app) {
                    capture(evidence.name("hidden"))
                    bar.buttons.element(boundBy: 0).tap()
                }
            } else {
                capture(evidence.name("hidden"))
                note("hidden: opened, but its screen did not settle")
            }
        } else {
            note("hidden: not in this build")
        }
        Gallery.tab(app, "Search").tap()
        try require(app.navigationBars["Search"].waitForExistence(timeout: 15), "The Search tab did not open.")
        capture(evidence.name("search"))
    }

    /// Opening Hidden asks for Face ID or the passcode straight away. The system draws that prompt
    /// over the app, out of reach of the tour's taps, and the app hides its Unlock button until the
    /// prompt ends. When it shows, the tour records it, then cancels it the way a person can: it
    /// leaves the app and comes back, and relaunches the app if the prompt outlasts that. Hidden
    /// stays locked either way. Returns whether the tour is still on Hidden.
    @MainActor
    private func passHiddenPrompt(_ app: XCUIApplication) throws -> Bool {
        let unlock = app.buttons["Unlock"]
        Gallery.settle(2)
        if unlock.exists {
            return true
        }
        capture(evidence.name("hiddenprompt"))
        XCUIDevice.shared.press(.home)
        app.activate()
        if unlock.waitForExistence(timeout: 15) {
            note("hidden: the Face ID or passcode prompt was cancelled by leaving the app")
            return true
        }
        app.terminate()
        app.launch()
        try require(app.tabBars.firstMatch.waitForExistence(timeout: 30),
                    "The tabs did not come back after relaunching past the Hidden prompt.")
        note("hidden: the prompt outlasted leaving the app, so the tour relaunched the app")
        return false
    }
}
