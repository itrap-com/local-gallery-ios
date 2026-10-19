import Foundation
import XCTest
@testable import GalleryCore

final class FavoriteListTests: XCTestCase {
    func testInitDropsDuplicatesAndEmpties() {
        XCTAssertEqual(FavoriteList(ids: ["a", "", "b", "a"]).ids, ["a", "b"])
    }

    func testToggleAddsNewestFirst() {
        var list = FavoriteList(ids: ["a"])
        list.toggle(["b"])
        XCTAssertEqual(list.ids, ["b", "a"])
    }

    func testToggleRemovesWhenAllAreFavorites() {
        var list = FavoriteList(ids: ["a", "b", "c"])
        list.toggle(["a", "c"])
        XCTAssertEqual(list.ids, ["b"])
    }

    func testMixedSelectionFavoritesTheRest() {
        var list = FavoriteList(ids: ["a"])
        list.toggle(["a", "b", "b"])
        XCTAssertEqual(list.ids, ["b", "a"])
    }

    func testEmptyToggleChangesNothing() {
        var list = FavoriteList(ids: ["a"])
        list.toggle([])
        list.toggle([""])
        XCTAssertEqual(list.ids, ["a"])
    }

    func testRoundTrip() throws {
        let list = FavoriteList(ids: ["x", "y"])
        XCTAssertEqual(try FavoriteList.decode(list.encoded()), list)
    }

    func testNewerFormatIsNotRead() throws {
        let data = Data(#"{"version":99,"ids":["x"]}"#.utf8)
        XCTAssertNil(try FavoriteList.decode(data))
    }

    func testDamagedDataThrows() {
        XCTAssertThrowsError(try FavoriteList.decode(Data("not json".utf8)))
    }
}
