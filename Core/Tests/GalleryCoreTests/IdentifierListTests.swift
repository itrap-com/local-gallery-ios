import Foundation
import XCTest
@testable import GalleryCore

final class IdentifierListTests: XCTestCase {
    func testInitDropsDuplicatesAndEmpties() {
        XCTAssertEqual(IdentifierList(ids: ["a", "", "b", "a"]).ids, ["a", "b"])
    }

    func testToggleAddsNewestFirst() {
        var list = IdentifierList(ids: ["a"])
        list.toggle(["b"])
        XCTAssertEqual(list.ids, ["b", "a"])
    }

    func testToggleRemovesWhenAllAreFavorites() {
        var list = IdentifierList(ids: ["a", "b", "c"])
        list.toggle(["a", "c"])
        XCTAssertEqual(list.ids, ["b"])
    }

    func testMixedSelectionFavoritesTheRest() {
        var list = IdentifierList(ids: ["a"])
        list.toggle(["a", "b", "b"])
        XCTAssertEqual(list.ids, ["b", "a"])
    }

    func testEmptyToggleChangesNothing() {
        var list = IdentifierList(ids: ["a"])
        list.toggle([])
        list.toggle([""])
        XCTAssertEqual(list.ids, ["a"])
    }

    func testRoundTrip() throws {
        let list = IdentifierList(ids: ["x", "y"])
        XCTAssertEqual(try IdentifierList.decode(list.encoded()), list)
    }

    func testNewerFormatIsNotRead() throws {
        let data = Data(#"{"version":99,"ids":["x"]}"#.utf8)
        XCTAssertNil(try IdentifierList.decode(data))
    }

    func testDamagedDataThrows() {
        XCTAssertThrowsError(try IdentifierList.decode(Data("not json".utf8)))
    }
}
