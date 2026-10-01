import Foundation

/// Faces found in a photo and how many of them have closed eyes.
public struct FaceSummary: Sendable, Equatable, Codable {
    public var count: Int
    public var closedEyes: Int

    public init(count: Int, closedEyes: Int) {
        self.count = count
        self.closedEyes = closedEyes
    }
}

public struct GroupingItem: Sendable {
    public var id: String
    public var creationDate: Date
    public var fingerprint: Fingerprint
    public var isFavorite: Bool
    public var isEdited: Bool
    public var pixelCount: Int
    /// Every resource of the asset on this phone.
    public var byteSize: Int64
    /// Bytes of the photo resource only, without a paired video or a RAW alternate. Nil falls back to `byteSize`.
    public var stillBytes: Int64?
    /// `ImageMetrics.fineToCoarse`, higher is sharper. Nil means unknown.
    public var sharpness: Double?
    /// Nil until the faces were analysed.
    public var faces: FaceSummary?

    public init(
        id: String, creationDate: Date, fingerprint: Fingerprint, isFavorite: Bool,
        isEdited: Bool, pixelCount: Int, byteSize: Int64,
        stillBytes: Int64? = nil, sharpness: Double? = nil, faces: FaceSummary? = nil
    ) {
        self.stillBytes = stillBytes
        self.sharpness = sharpness
        self.faces = faces
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
    /// Measured on Vision revision 2: same-scene variants reach 0.44, different scenes start at 0.72.
    public var maxDistance: Float = 0.45
    public var maxNeighbors = 30
    public var maxInterval: TimeInterval = 600

    public init() {}
}

/// Why the best photo of a group is best, from the verdict against the runner-up.
public enum KeeperReason: Sendable, Equatable {
    case favourite, edited, resolution, eyes, size, sharpness, sizeAndSharpness
    /// No vote cleared its margin: the larger still won by exact bytes, or the earliest photo won.
    case tie
}

public enum KeeperConfidence: Sendable, Equatable {
    case clear, close
}

/// How much a vote must differ to count. Measured on 16 photographs: adjacent video frames differ by at most
/// 2.4 percent in file size and 5.3 percent in sharpness, two framings of one photo by at most 0.6 and 8.1 percent.
public struct KeeperPolicy: Sendable, Equatable {
    public var sizeBand = 0.05
    public var sharpnessBand = 0.10

    public init() {}

    struct Verdict {
        /// 1 when the first photo is better, -1 when the second is, 0 when nothing separates them.
        var winner: Int
        var reason: KeeperReason
        var isClear: Bool
    }

    func verdict(_ a: GroupingItem, _ b: GroupingItem) -> Verdict {
        if a.isFavorite != b.isFavorite { return Verdict(winner: a.isFavorite ? 1 : -1, reason: .favourite, isClear: true) }
        if a.isEdited != b.isEdited { return Verdict(winner: a.isEdited ? 1 : -1, reason: .edited, isClear: true) }
        if a.pixelCount != b.pixelCount {
            return Verdict(winner: a.pixelCount > b.pixelCount ? 1 : -1, reason: .resolution, isClear: true)
        }

        var votes: [(reason: KeeperReason, side: Int)] = []
        if let x = a.faces, let y = b.faces, x.count == y.count, x.closedEyes != y.closedEyes {
            votes.append((.eyes, x.closedEyes < y.closedEyes ? 1 : -1))
        }
        let sizeA = Self.bytes(a), sizeB = Self.bytes(b)
        if sizeA > 0, sizeB > 0, abs(log(Double(sizeA) / Double(sizeB))) > log(1 + sizeBand) {
            votes.append((.size, sizeA > sizeB ? 1 : -1))
        }
        if let sharpA = a.sharpness, let sharpB = b.sharpness, sharpA > 0, sharpB > 0,
           abs(log(sharpA / sharpB)) > log(1 + sharpnessBand) {
            votes.append((.sharpness, sharpA > sharpB ? 1 : -1))
        }
        guard let first = votes.first else {
            let winner = sizeA == sizeB ? 0 : (sizeA > sizeB ? 1 : -1)
            return Verdict(winner: winner, reason: .tie, isClear: false)
        }
        let agree = Set(votes.map(\.side)).count == 1
        let sizeAndSharpness = first.reason == .size && votes.count == 2
        return Verdict(winner: first.side, reason: agree && sizeAndSharpness ? .sizeAndSharpness : first.reason, isClear: agree)
    }

    /// A missing or zero still size (no resource reported one) falls back to the asset total.
    static func bytes(_ item: GroupingItem) -> Int64 {
        guard let still = item.stillBytes, still > 0 else { return item.byteSize }
        return still
    }
}

public struct SimilarityGroup: Sendable, Equatable {
    public let keeperID: String
    /// Members in creation order, keeper included.
    public let memberIDs: [String]
    /// Members from best to worst, keeper first.
    public let rankedMemberIDs: [String]
    /// Everything except the keeper, favourites and edited photos, close call or not. Leaving the near-equal
    /// contenders unticked would protect against a coin-flip Best but starts a burst of near-identical frames with
    /// nothing ticked, which costs review time: that is an owner decision, so a close call only carries a label.
    public let suggestedRemovalIDs: [String]
    public let keeperReason: KeeperReason
    public let confidence: KeeperConfidence
    /// Members the keeper does not clearly beat. A close call needs one that is not a favourite or edited photo.
    public let contenderIDs: [String]
    /// One plain sentence for the group header.
    public let reasonLine: String
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

    /// Favourite, then edited, then resolution, then the votes of the still's bytes (5 percent margin) and
    /// sharpness (10 percent margin), then the earliest photo. Without votes the larger still wins by exact bytes,
    /// which is the order measured on 16 photographs against recompressed, cropped, downsized and blurred copies:
    /// file size picked the original 16 times of 16, Laplacian sharpness only 1 of 16 because JPEG blocking adds
    /// edges. Margins are not transitive, so the best photo is found by repeated champion selection over creation
    /// order: a challenger replaces the champion only by beating it, so ties keep the earliest.
    static func ranked(_ members: [GroupingItem], policy: KeeperPolicy = .init()) -> [GroupingItem] {
        var remaining = members
        var order: [GroupingItem] = []
        while !remaining.isEmpty {
            var champion = 0
            for challenger in remaining.indices.dropFirst()
            where policy.verdict(remaining[challenger], remaining[champion]).winner > 0 {
                champion = challenger
            }
            order.append(remaining.remove(at: champion))
        }
        return order
    }

    static func keeper(of members: [GroupingItem]) -> GroupingItem {
        ranked(members)[0]
    }

    private static func makeGroup(_ members: [GroupingItem]) -> SimilarityGroup {
        let policy = KeeperPolicy()
        let ranked = ranked(members, policy: policy)
        let keeper = ranked[0]
        let reference = ranked.dropFirst().first { !$0.isFavorite && !$0.isEdited } ?? ranked[1]
        let runnerUp = policy.verdict(keeper, reference)
        let contenders = members.filter { member in
            guard member.id != keeper.id else { return false }
            let verdict = policy.verdict(keeper, member)
            return !(verdict.winner > 0 && verdict.isClear)
        }
        let isClose = contenders.contains { !$0.isFavorite && !$0.isEdited }
        let keeperReason: KeeperReason = runnerUp.reason == .tie && !isClose
            ? (keeper.isFavorite ? .favourite : .edited) : runnerUp.reason
        return SimilarityGroup(
            keeperID: keeper.id,
            memberIDs: members.map(\.id),
            rankedMemberIDs: ranked.map(\.id),
            suggestedRemovalIDs: members
                .filter { $0.id != keeper.id && !$0.isFavorite && !$0.isEdited }
                .map(\.id),
            keeperReason: keeperReason,
            confidence: isClose ? .close : .clear,
            contenderIDs: contenders.map(\.id),
            reasonLine: isClose
                ? closeCallLine
                : reasonLine(keeper: keeper, runnerUp: reference, others: ranked.dropFirst(), reason: keeperReason)
        )
    }

    private static let closeCallLine = "Close call. Check these before deleting. One is marked Best."

    private static func reasonLine(
        keeper: GroupingItem, runnerUp: GroupingItem, others: ArraySlice<GroupingItem>, reason: KeeperReason
    ) -> String {
        func percent(_ better: Double, _ worse: Double) -> Int? {
            guard better > 0, worse > 0 else { return nil }
            let gain = ((better / worse - 1) * 100).rounded()
            return gain.isFinite ? Int(gain) : nil
        }
        func suffix(_ gain: Int?) -> String { gain.map { " (+\($0)%)" } ?? "" }
        func megapixels(_ item: GroupingItem) -> Int { Int((Double(item.pixelCount) / 1_000_000).rounded()) }
        func sizeGain() -> Int? { percent(Double(KeeperPolicy.bytes(keeper)), Double(KeeperPolicy.bytes(runnerUp))) }
        func sharpnessGain() -> Int? { percent(keeper.sharpness ?? 0, runnerUp.sharpness ?? 0) }
        switch reason {
        case .favourite: return "Best: you marked it as a favourite."
        case .edited: return "Best: you edited it."
        case .resolution:
            return "Best: more pixels (\(megapixels(keeper)) MP, the others \(megapixels(runnerUp)) MP)."
        case .eyes:
            let worse = others.filter { ($0.faces?.closedEyes ?? 0) > (keeper.faces?.closedEyes ?? 0) }.count
            return worse == 1 ? "Best: eyes open. 1 other has closed eyes."
                : "Best: eyes open. \(worse) others have closed eyes."
        case .sizeAndSharpness: return "Best: sharper, larger file\(suffix(sizeGain()))."
        case .size: return "Best: larger file, more detail\(suffix(sizeGain()))."
        case .sharpness: return "Best: sharper\(suffix(sharpnessGain()))."
        case .tie: return closeCallLine
        }
    }
}
