import Foundation

/// The app-local favorites: PhotoKit identifiers, most recently added first, without duplicates.
///
/// Favorites never touch the photo library. An identifier whose item has gone simply matches
/// nothing; the list is never treated as proof that an item exists.
public struct FavoriteList: Equatable, Sendable {
    public private(set) var ids: [String]

    public init(ids: [String] = []) {
        var seen = Set<String>()
        self.ids = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    /// Favorites every identifier unless all of them already are; then it removes them all.
    /// This is the batch rule for a selection: one tap makes the whole selection agree.
    public mutating func toggle(_ batch: [String]) {
        let wanted = batch.filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return }
        let current = Set(ids)
        if wanted.allSatisfy(current.contains) {
            let removing = Set(wanted)
            ids.removeAll { removing.contains($0) }
        } else {
            var seen = current
            let added = wanted.filter { seen.insert($0).inserted }
            ids.insert(contentsOf: added, at: 0)
        }
    }

    public mutating func remove(_ batch: [String]) {
        let removing = Set(batch)
        ids.removeAll { removing.contains($0) }
    }

    // MARK: Storage format

    private struct Stored: Codable {
        var version: Int
        var ids: [String]
    }

    public static let formatVersion = 1

    public func encoded() throws -> Data {
        try JSONEncoder().encode(Stored(version: Self.formatVersion, ids: ids))
    }

    /// Reads a stored list. Returns nil for data written by a newer format, so it is never
    /// overwritten by a downgrade; throws for damaged data.
    public static func decode(_ data: Data) throws -> FavoriteList? {
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        guard stored.version <= formatVersion else { return nil }
        return FavoriteList(ids: stored.ids)
    }
}
