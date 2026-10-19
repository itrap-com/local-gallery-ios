import Foundation

/// A kind of item the search box understands by name.
public enum SearchKind: String, CaseIterable, Sendable {
    case photo
    case video
    case screenshot
    case selfie
    case live
    case panorama
    case favorite
}

/// The date part of a search: a year, a month in any year, or a month of one year.
public enum DateMatch: Equatable, Sendable {
    case year(Int)
    case month(Int)
    case monthOfYear(month: Int, year: Int)

    /// The half-open interval to fetch, when the match is one contiguous span.
    public func interval(in calendar: Calendar) -> DateInterval? {
        let start: DateComponents
        let length: DateComponents
        switch self {
        case .month:
            return nil
        case .year(let year):
            start = DateComponents(year: year, month: 1, day: 1)
            length = DateComponents(year: 1)
        case .monthOfYear(let month, let year):
            start = DateComponents(year: year, month: month, day: 1)
            length = DateComponents(month: 1)
        }
        guard let from = calendar.date(from: start),
              let to = calendar.date(byAdding: length, to: from)
        else { return nil }
        return DateInterval(start: from, end: to)
    }

    public func matches(_ date: Date, in calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.year, .month], from: date)
        switch self {
        case .year(let year):
            return parts.year == year
        case .month(let month):
            return parts.month == month
        case .monthOfYear(let month, let year):
            return parts.month == month && parts.year == year
        }
    }
}

/// What the owner typed, parsed locally. Search text never leaves the device and is never logged.
///
/// Recognised words become kinds ("videos", "selfie") and dates ("2024", "october", "oct 2023");
/// every other word is a text term matched against album names.
public struct SearchQuery: Equatable, Sendable {
    public var kinds: Set<SearchKind>
    public var date: DateMatch?
    public var terms: [String]

    public init(kinds: Set<SearchKind> = [], date: DateMatch? = nil, terms: [String] = []) {
        self.kinds = kinds
        self.date = date
        self.terms = terms
    }

    public var isEmpty: Bool { kinds.isEmpty && date == nil && terms.isEmpty }

    static let kindWords: [String: SearchKind] = [
        "photo": .photo, "photos": .photo, "picture": .photo, "pictures": .photo, "image": .photo,
        "images": .photo, "pic": .photo, "pics": .photo,
        "video": .video, "videos": .video, "movie": .video, "movies": .video, "clip": .video,
        "clips": .video,
        "screenshot": .screenshot, "screenshots": .screenshot,
        "selfie": .selfie, "selfies": .selfie,
        "live": .live,
        "panorama": .panorama, "panoramas": .panorama, "pano": .panorama, "panos": .panorama,
        "favorite": .favorite, "favorites": .favorite, "favourite": .favorite,
        "favourites": .favorite, "fav": .favorite, "favs": .favorite, "loved": .favorite,
    ]

    static let monthWords: [String: Int] = {
        let names = ["january", "february", "march", "april", "may", "june", "july", "august",
                     "september", "october", "november", "december"]
        var words: [String: Int] = [:]
        for (index, name) in names.enumerated() {
            words[name] = index + 1
            words[String(name.prefix(3))] = index + 1
        }
        words["sept"] = 9
        return words
    }()

    /// Words that only glue a query together ("videos from 2024").
    static let fillerWords: Set<String> = ["in", "from", "of", "the", "and", "on", "at", "my"]

    public static func parse(_ text: String) -> SearchQuery {
        var query = SearchQuery()
        var month: Int?
        var year: Int?
        let words = text.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
            .map(String.init)
        for word in words {
            if let kind = kindWords[word] {
                query.kinds.insert(kind)
            } else if let number = Int(word), word.count == 4, (1900...2100).contains(number), year == nil {
                year = number
            } else if let value = monthWords[word], month == nil {
                month = value
            } else if fillerWords.contains(word) {
                continue
            } else {
                query.terms.append(word)
            }
        }
        switch (month, year) {
        case let (month?, year?): query.date = .monthOfYear(month: month, year: year)
        case let (month?, nil): query.date = .month(month)
        case let (nil, year?): query.date = .year(year)
        case (nil, nil): query.date = nil
        }
        // "live photos" asks for Live Photos, not every photo.
        if query.kinds.contains(.live) || query.kinds.contains(.screenshot)
            || query.kinds.contains(.selfie) || query.kinds.contains(.panorama) {
            query.kinds.remove(.photo)
        }
        return query
    }
}
