import Foundation

public struct GroupingItem: Sendable {
    public var id: String
    public var creationDate: Date
    public var fingerprint: Fingerprint
    public var isFavorite: Bool
    public var isEdited: Bool
    public var pixelCount: Int
    /// Every resource of the asset on this phone.
    public var byteSize: Int64

    public init(
        id: String, creationDate: Date, fingerprint: Fingerprint, isFavorite: Bool,
        isEdited: Bool, pixelCount: Int, byteSize: Int64
    ) {
        self.id = id
        self.creationDate = creationDate
        self.fingerprint = fingerprint
        self.isFavorite = isFavorite
        self.isEdited = isEdited
        self.pixelCount = pixelCount
        self.byteSize = byteSize
    }
}

public struct SimilarityRules: Sendable, Equatable {
    /// Measured on Vision revision 2: same-scene variants reach 0.44, different scenes start at 0.74.
    public var maxDistance: Float = 0.45
    public var maxNeighbors = 30
    public var maxInterval: TimeInterval = 600

    public init() {}
}

public struct SimilarityGroup: Sendable, Equatable {
    public let keeperID: String
    /// Members in creation order, keeper included.
    public let memberIDs: [String]
    /// Members from best to worst, keeper first.
    public let rankedMemberIDs: [String]
    /// Everything except the keeper, favourites and edited photos.
    public let suggestedRemovalIDs: [String]
}

public enum SimilarityGrouper {
    /// Leader clustering over creation order: each photo joins the earliest group whose first
    /// photo it resembles, so a slow drift across a burst cannot merge the two ends.
    public static func groups(from items: [GroupingItem], rules: SimilarityRules = .init()) -> [SimilarityGroup] {
        let sorted = items.sorted { ($0.creationDate, $0.id) < ($1.creationDate, $1.id) }
        var assigned = Set<Int>()
        var groups: [SimilarityGroup] = []

        for leader in sorted.indices where !assigned.contains(leader) {
            var members = [leader]
            let leaderFloats = sorted[leader].fingerprint.floats
            let lastCandidate = min(sorted.count - 1, leader + rules.maxNeighbors)
            if leader < lastCandidate {
                for candidate in (leader + 1)...lastCandidate where !assigned.contains(candidate) {
                    let gap = sorted[candidate].creationDate.timeIntervalSince(sorted[leader].creationDate)
                    if gap > rules.maxInterval { break }
                    if sorted[candidate].fingerprint.distance(toFloats: leaderFloats) <= rules.maxDistance {
                        members.append(candidate)
                    }
                }
            }
            guard members.count > 1 else { continue }
            assigned.formUnion(members)
            groups.append(makeGroup(members.map { sorted[$0] }))
        }
        return groups
    }

    /// Favourite, then edited, then resolution, then file size, then the earliest photo.
    /// At equal resolution the larger file kept more detail. Measured on 16 photographs against
    /// recompressed, cropped, downsized and blurred copies: file size picked the original 16 times
    /// of 16, Laplacian sharpness only 1 of 16 because JPEG blocking adds edges.
    static func ranked(_ members: [GroupingItem]) -> [GroupingItem] {
        func key(_ entry: (offset: Int, element: GroupingItem)) -> (Int, Int, Int, Int64, Int) {
            (entry.element.isFavorite ? 1 : 0, entry.element.isEdited ? 1 : 0,
             entry.element.pixelCount, entry.element.byteSize, -entry.offset)
        }
        return members.enumerated().sorted { key($0) > key($1) }.map(\.element)
    }

    static func keeper(of members: [GroupingItem]) -> GroupingItem {
        ranked(members)[0]
    }

    private static func makeGroup(_ members: [GroupingItem]) -> SimilarityGroup {
        let ranked = ranked(members)
        let keeper = ranked[0]
        return SimilarityGroup(
            keeperID: keeper.id,
            memberIDs: members.map(\.id),
            rankedMemberIDs: ranked.map(\.id),
            suggestedRemovalIDs: members
                .filter { $0.id != keeper.id && !$0.isFavorite && !$0.isEdited }
                .map(\.id)
        )
    }
}
