import Foundation
import XCTest
@testable import GalleryCore

final class TimelineGroupingTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testEmptyListHasNoSections() {
        XCTAssertEqual(TimelineGrouping.monthSections(dates: [], calendar: utc), [])
    }

    func testSingleItemIsOneSection() {
        let sections = TimelineGrouping.monthSections(dates: [date(2026, 10, 18)], calendar: utc)
        XCTAssertEqual(sections, [TimelineSection(month: MonthKey(year: 2026, month: 10), range: 0..<1)])
    }

    func testEachContiguousMonthIsOneSection() {
        let dates: [Date?] = [date(2026, 10, 18), date(2026, 10, 1), date(2026, 9, 30), date(2025, 9, 30)]
        let sections = TimelineGrouping.monthSections(dates: dates, calendar: utc)
        XCTAssertEqual(sections.map(\.range), [0..<2, 2..<3, 3..<4])
        XCTAssertEqual(sections.map(\.month), [
            MonthKey(year: 2026, month: 10),
            MonthKey(year: 2026, month: 9),
            MonthKey(year: 2025, month: 9),
        ])
    }

    func testMissingDatesStayWhereTheSortPutThem() {
        let dates: [Date?] = [date(2026, 10, 18), nil, nil, date(2026, 10, 2)]
        let sections = TimelineGrouping.monthSections(dates: dates, calendar: utc)
        XCTAssertEqual(sections.map(\.range), [0..<1, 1..<3, 3..<4])
        XCTAssertNil(sections[1].month)
    }

    func testEveryIndexIsCoveredExactlyOnce() {
        let dates: [Date?] = [nil, date(2024, 1, 1), date(2024, 1, 2), nil, date(2023, 12, 31)]
        let sections = TimelineGrouping.monthSections(dates: dates, calendar: utc)
        let covered = sections.flatMap { Array($0.range) }
        XCTAssertEqual(covered, Array(0..<dates.count))
    }

    func testSectionIdentityIsItsFirstIndex() {
        let sections = TimelineGrouping.monthSections(dates: [date(2026, 1, 1), date(2025, 1, 1)], calendar: utc)
        XCTAssertEqual(sections.map(\.id), [0, 1])
    }
}
