import Photos
import XCTest
@testable import LocalGallery

final class LibraryAccessTests: XCTestCase {
    func testEveryAuthorizationStatusMapsToADesignedState() {
        XCTAssertEqual(LibraryAccess(.notDetermined), .notDetermined)
        XCTAssertEqual(LibraryAccess(.denied), .denied)
        XCTAssertEqual(LibraryAccess(.restricted), .restricted)
        XCTAssertEqual(LibraryAccess(.limited), .limited)
        XCTAssertEqual(LibraryAccess(.authorized), .full)
    }

    func testOnlyFullAndLimitedAccessCanRead() {
        XCTAssertTrue(LibraryAccess.full.canRead)
        XCTAssertTrue(LibraryAccess.limited.canRead)
        XCTAssertFalse(LibraryAccess.denied.canRead)
        XCTAssertFalse(LibraryAccess.restricted.canRead)
        XCTAssertFalse(LibraryAccess.notDetermined.canRead)
    }
}
