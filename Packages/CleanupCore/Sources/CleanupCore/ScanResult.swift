import Foundation

public enum CleanupCategory: String, CaseIterable, Identifiable, Sendable {
    case screenshots, similar, lowQuality, bigVideos

    public var id: String { rawValue }
}

public struct CleanupItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let byteSize: Int64
    public let creationDate: Date
    public let duration: TimeInterval?
    public let badge: String?
    public let screenshotKind: ScreenshotKind?
    public var isKeeper: Bool
    public let isFavorite: Bool
    public let isEdited: Bool

    /// A favourite or an edited photo: a bulk action never selects it, the user can still tick it by hand.
    public var isProtected: Bool { isFavorite || isEdited }

    public init(
        id: String, byteSize: Int64, creationDate: Date, duration: TimeInterval? = nil,
        badge: String? = nil, screenshotKind: ScreenshotKind? = nil, isKeeper: Bool = false,
        isFavorite: Bool = false, isEdited: Bool = false
    ) {
        self.id = id
        self.byteSize = byteSize
        self.creationDate = creationDate
        self.duration = duration
        self.badge = badge
        self.screenshotKind = screenshotKind
        self.isKeeper = isKeeper
        self.isFavorite = isFavorite
        self.isEdited = isEdited
    }
}

/// The screenshots of one kind, as shown under one heading.
public struct ScreenshotSection: Identifiable, Sendable, Hashable {
    public let kind: ScreenshotKind
    public let items: [CleanupItem]

    public var id: String { kind.rawValue }

    public var byteSize: Int64 { items.reduce(0) { $0 + $1.byteSize } }

    /// What this heading's Select button ticks: everything except favourites and edited photos.
    public var bulkSelectableIDs: Set<String> { Set(items.filter { !$0.isProtected }.map(\.id)) }

    public var protectedCountLeftOut: Int { items.filter(\.isProtected).count }
}

public struct SimilarGroup: Identifiable, Sendable, Hashable {
    /// Stable for the life of the group, even when the best photo changes.
    public let id: String
    public private(set) var items: [CleanupItem]
    public private(set) var suggestedRemovalIDs: Set<String>
    /// Every member from best to worst. Picks the next best photo when the current one goes.
    public let rankedIDs: [String]

    public init(id: String, items: [CleanupItem], suggestedRemovalIDs: Set<String>, rankedIDs: [String]) {
        self.id = id
        self.items = items
        self.suggestedRemovalIDs = suggestedRemovalIDs
        self.rankedIDs = rankedIDs
    }

    public var keeperID: String? { items.first(where: \.isKeeper)?.id }

    public var removableCount: Int { items.filter { !$0.isKeeper }.count }

    public var reclaimableBytes: Int64 {
        items.filter { !$0.isKeeper }.reduce(0) { $0 + $1.byteSize }
    }

    /// Nil when fewer than two photos are left: a group of one is no group.
    /// When the best photo is among the removed, the best of the rest takes its place and is
    /// no longer suggested for removal.
    func removing(_ ids: Set<String>) -> SimilarGroup? {
        var remaining = items.filter { !ids.contains($0.id) }
        guard remaining.count > 1 else { return nil }
        var suggested = suggestedRemovalIDs.subtracting(ids)
        if !remaining.contains(where: \.isKeeper),
           let promoted = rankedIDs.first(where: { id in remaining.contains { $0.id == id } }),
           let index = remaining.firstIndex(where: { $0.id == promoted }) {
            remaining[index].isKeeper = true
            suggested.remove(promoted)
        }
        return SimilarGroup(id: id, items: remaining, suggestedRemovalIDs: suggested, rankedIDs: rankedIDs)
    }
}

public struct ScanResult: Sendable {
    public var screenshots: [CleanupItem]
    public var similarGroups: [SimilarGroup]
    public var lowQuality: [CleanupItem]
    public var bigVideos: [CleanupItem]
    public var notOnDevice: Int
    public var scannedPhotos: Int

    public init(
        screenshots: [CleanupItem] = [], similarGroups: [SimilarGroup] = [], lowQuality: [CleanupItem] = [],
        bigVideos: [CleanupItem] = [], notOnDevice: Int = 0, scannedPhotos: Int = 0
    ) {
        self.screenshots = screenshots
        self.similarGroups = similarGroups
        self.lowQuality = lowQuality
        self.bigVideos = bigVideos
        self.notOnDevice = notOnDevice
        self.scannedPhotos = scannedPhotos
    }

    /// Puts the screenshots in the order they are shown: kinds biggest first with "mix" last, newest first
    /// inside a kind. Call it once when a scan ends. The order then stays, so deleting from one kind never
    /// moves it below another while the user is looking at the list.
    public mutating func arrangeScreenshots() {
        var bytes: [ScreenshotKind: Int64] = [:]
        for item in screenshots { bytes[item.screenshotKind ?? .mix, default: 0] += item.byteSize }
        let kinds = bytes.keys.sorted { a, b in
            if (a == .mix) != (b == .mix) { return b == .mix }
            if bytes[a] != bytes[b] { return (bytes[a] ?? 0) > (bytes[b] ?? 0) }
            return a.rawValue < b.rawValue
        }
        let rank = Dictionary(uniqueKeysWithValues: kinds.enumerated().map { ($1, $0) })
        screenshots.sort { a, b in
            let (rankA, rankB) = (rank[a.screenshotKind ?? .mix] ?? 0, rank[b.screenshotKind ?? .mix] ?? 0)
            if rankA != rankB { return rankA < rankB }
            if a.creationDate != b.creationDate { return a.creationDate > b.creationDate }
            return a.id < b.id
        }
    }

    /// The screenshots grouped by kind, in the order they stand in `screenshots`.
    public var screenshotSections: [ScreenshotSection] {
        var order: [ScreenshotKind] = []
        var grouped: [ScreenshotKind: [CleanupItem]] = [:]
        for item in screenshots {
            let kind = item.screenshotKind ?? .mix
            if grouped[kind] == nil { order.append(kind) }
            grouped[kind, default: []].append(item)
        }
        return order.map { ScreenshotSection(kind: $0, items: grouped[$0] ?? []) }
    }

    /// In the order they are shown, so "above" and "below" mean the same here and on screen.
    public func items(in category: CleanupCategory) -> [CleanupItem] {
        switch category {
        case .screenshots: screenshotSections.flatMap(\.items)
        case .similar: similarGroups.flatMap(\.items)
        case .lowQuality: lowQuality
        case .bigVideos: bigVideos
        }
    }

    /// Count of items the user could remove. In similar groups the best shot of each group stays.
    public func removableCount(in category: CleanupCategory) -> Int {
        category == .similar ? similarGroups.reduce(0) { $0 + $1.removableCount } : items(in: category).count
    }

    public func reclaimableBytes(in category: CleanupCategory) -> Int64 {
        category == .similar
            ? similarGroups.reduce(0) { $0 + $1.reclaimableBytes }
            : items(in: category).reduce(0) { $0 + $1.byteSize }
    }

    public var totalReclaimableBytes: Int64 {
        CleanupCategory.allCases.reduce(0) { $0 + reclaimableBytes(in: $1) }
    }

    public var allIDs: Set<String> {
        CleanupCategory.allCases.reduce(into: Set<String>()) { $0.formUnion(items(in: $1).map(\.id)) }
    }

    public func byteSize(of ids: Set<String>) -> Int64 {
        var seen = Set<String>()
        var total: Int64 = 0
        for category in CleanupCategory.allCases {
            for item in items(in: category) where ids.contains(item.id) && seen.insert(item.id).inserted {
                total += item.byteSize
            }
        }
        return total
    }

    /// The non-best photos of every similar group, minus favourites and edited photos.
    public var suggestedSelection: Set<String> {
        similarGroups.reduce(into: Set<String>()) { $0.formUnion($1.suggestedRemovalIDs) }
    }

    /// What "Select all" ticks. Similar groups: the suggestion. Every other category: everything except
    /// favourites and edited photos.
    public func bulkSelectableIDs(in category: CleanupCategory) -> Set<String> {
        category == .similar ? suggestedSelection : Set(items(in: category).filter { !$0.isProtected }.map(\.id))
    }

    /// Favourites and edited photos "Select all" leaves out. Zero for similar groups, whose suggestion
    /// already leaves the best photo and the protected ones unticked.
    public func protectedCountLeftOut(in category: CleanupCategory) -> Int {
        category == .similar ? 0 : items(in: category).filter(\.isProtected).count
    }

    /// The best photo of every similar group.
    public var keeperIDs: Set<String> {
        Set(similarGroups.flatMap(\.items).filter(\.isKeeper).map(\.id))
    }

    public func removing(ids: Set<String>) -> ScanResult {
        var copy = self
        copy.screenshots.removeAll { ids.contains($0.id) }
        copy.lowQuality.removeAll { ids.contains($0.id) }
        copy.bigVideos.removeAll { ids.contains($0.id) }
        copy.similarGroups = similarGroups.compactMap { $0.removing(ids) }
        return copy
    }
}
