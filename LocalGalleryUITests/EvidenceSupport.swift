import XCTest

/// What the iOS evidence workflow set up on the simulator before a run: the photo-access state, the
/// appearance and the text size. It passes them as TEST_RUNNER_LG_* variables, which reach the test
/// runner without the prefix. Without LG_ACCESS_STATE these tests skip, so a plain run of the
/// scheme, as ci.yml does, stays quick.
struct Evidence {
    enum Access: String {
        case full, limited, denied, notdetermined, empty
    }

    let access: Access
    let appearance: String
    let textSize: String

    static func current() throws -> Evidence {
        let environment = ProcessInfo.processInfo.environment
        guard let raw = environment["LG_ACCESS_STATE"], !raw.isEmpty else {
            throw XCTSkip("Runs only in the iOS evidence workflow, which sets LG_ACCESS_STATE.")
        }
        guard let access = Access(rawValue: raw) else {
            throw EvidenceError("Unknown LG_ACCESS_STATE: \(raw)")
        }
        return Evidence(
            access: access,
            appearance: value(environment["LG_APPEARANCE"]),
            textSize: value(environment["LG_TEXT_SIZE"])
        )
    }

    /// The attachment name the workflow exports: <screen>-<access>-<appearance>-<textsize>.
    func name(_ screen: String) -> String {
        "\(screen)-\(access.rawValue)-\(appearance)-\(textSize)"
    }

    private static func value(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "unset" }
        return raw
    }
}

/// A broken precondition: the app does not show the state the workflow set up, so no screenshot
/// is taken under that state's name.
struct EvidenceError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw EvidenceError(message)
    }
}

/// Queries for the app's screens. The app has no test identifiers, so these match what people see
/// and hear: tab titles, button names and the generic tile labels.
@MainActor
enum Gallery {
    /// Grid tiles are one accessibility element each, labelled "Photo" or "Video, N seconds".
    static func tiles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label == 'Photo' OR label BEGINSWITH 'Photo, ' OR label BEGINSWITH 'Video, '"
        ))
    }

    static func tab(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.tabBars.buttons[title]
    }

    /// Lets animations finish and thumbnails arrive, without blocking the run loop.
    static func settle(_ seconds: TimeInterval = 1.5) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }
}

extension XCTestCase {
    /// Attaches a screenshot of the whole screen under its export name, kept when tests pass too.
    @MainActor
    func capture(_ name: String) {
        Gallery.settle()
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Records a note in the result bundle, such as a screen this build does not have.
    @MainActor
    func note(_ text: String) {
        XCTContext.runActivity(named: text) { _ in }
    }
}
