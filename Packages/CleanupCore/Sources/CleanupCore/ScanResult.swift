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
    public var isKeeper: Bool

    public init(
        id: String, byteSize: Int64, creationDate: Date, duration: TimeInterval? = nil,
        badge: String? = nil, isKeeper: Bool = false
    ) {
        self.id = id
        self.byteSize = byteSize
        self.creationDate = creationDate
        self.duration = duration
        self.badge = badge
        self.isKeeper = isKeeper
    }
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

    public func items(in category: CleanupCategory) -> [CleanupItem] {
        switch category {
        case .screenshots: screenshots
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
