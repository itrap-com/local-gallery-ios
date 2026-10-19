import Foundation
import XCTest
@testable import GalleryCore

final class SearchQueryTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testEmptyTextIsEmptyQuery() {
        XCTAssertTrue(SearchQuery.parse("").isEmpty)
        XCTAssertTrue(SearchQuery.parse("  ,. ").isEmpty)
    }

    func testKindWordsAndPlurals() {
        XCTAssertEqual(SearchQuery.parse("Videos").kinds, [.video])
        XCTAssertEqual(SearchQuery.parse("selfie").kinds, [.selfie])
        XCTAssertEqual(SearchQuery.parse("favourites").kinds, [.favorite])
    }

    func testLivePhotosMeansLiveOnly() {
        XCTAssertEqual(SearchQuery.parse("live photos").kinds, [.live])
        XCTAssertEqual(SearchQuery.parse("screenshot pictures").kinds, [.screenshot])
    }

    func testYearMonthAndBoth() {
        XCTAssertEqual(SearchQuery.parse("2024").date, .year(2024))
        XCTAssertEqual(SearchQuery.parse("october").date, .month(10))
        XCTAssertEqual(SearchQuery.parse("Oct 2023").date, .monthOfYear(month: 10, year: 2023))
        XCTAssertEqual(SearchQuery.parse("2023 sept").date, .monthOfYear(month: 9, year: 2023))
    }

    func testNumbersThatAreNotYearsAreTerms() {
        let query = SearchQuery.parse("trip 42 12345")
        XCTAssertNil(query.date)
        XCTAssertEqual(query.terms, ["trip", "42", "12345"])
    }

    func testFillerWordsAreDroppedAndTheRestAreTerms() {
        let query = SearchQuery.parse("videos from the Beach trip in 2024")
        XCTAssertEqual(query.kinds, [.video])
        XCTAssertEqual(query.date, .year(2024))
        XCTAssertEqual(query.terms, ["beach", "trip"])
    }

    func testYearInterval() {
        let interval = DateMatch.year(2024).interval(in: utc)
        XCTAssertEqual(interval?.start, utc.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        XCTAssertEqual(interval?.end, utc.date(from: DateComponents(year: 2025, month: 1, day: 1)))
    }

    func testMonthOfYearIntervalCrossesYearEnd() {
        let interval = DateMatch.monthOfYear(month: 12, year: 2023).interval(in: utc)
        XCTAssertEqual(interval?.start, utc.date(from: DateComponents(year: 2023, month: 12, day: 1)))
        XCTAssertEqual(interval?.end, utc.date(from: DateComponents(year: 2024, month: 1, day: 1)))
    }

    func testMonthOnlyHasNoIntervalButMatchesAnyYear() {
        XCTAssertNil(DateMatch.month(3).interval(in: utc))
        let march2019 = utc.date(from: DateComponents(year: 2019, month: 3, day: 15))!
        let april2019 = utc.date(from: DateComponents(year: 2019, month: 4, day: 15))!
        XCTAssertTrue(DateMatch.month(3).matches(march2019, in: utc))
        XCTAssertFalse(DateMatch.month(3).matches(april2019, in: utc))
    }
}
