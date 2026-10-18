import Foundation

/// A calendar month, used as a timeline section key.
public struct MonthKey: Hashable, Sendable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }
}

/// A contiguous run of timeline items that share a month. `range` indexes into the sorted list
/// the sections were built from; `month` is nil for items without a capture date.
public struct TimelineSection: Identifiable, Hashable, Sendable {
    public let month: MonthKey?
    public let range: Range<Int>

    public var id: Int { range.lowerBound }

    public init(month: MonthKey?, range: Range<Int>) {
        self.month = month
        self.range = range
    }
}

public enum TimelineGrouping {
    /// Splits an already-sorted list into contiguous runs of the same calendar month.
    ///
    /// Nothing is reordered and no date is invented: items without a date form their own runs
    /// wherever the sort placed them, and every index lands in exactly one section.
    public static func monthSections(dates: [Date?], calendar: Calendar) -> [TimelineSection] {
        guard let first = dates.first else { return [] }

        func key(_ date: Date?) -> MonthKey? {
            guard let date else { return nil }
            let parts = calendar.dateComponents([.year, .month], from: date)
            guard let year = parts.year, let month = parts.month else { return nil }
            return MonthKey(year: year, month: month)
        }

        var sections: [TimelineSection] = []
        var runStart = 0
        var runKey = key(first)
        for index in 1..<dates.count {
            let next = key(dates[index])
            if next != runKey {
                sections.append(TimelineSection(month: runKey, range: runStart..<index))
                runStart = index
                runKey = next
            }
        }
        sections.append(TimelineSection(month: runKey, range: runStart..<dates.count))
        return sections
    }
}
