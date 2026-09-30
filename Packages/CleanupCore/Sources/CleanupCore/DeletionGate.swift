import Foundation

/// What the scan or the library says about one photo that can change behind the app's back.
/// `hasAdjustments` is left out on purpose: the app infers "edited" from resource types, so the two
/// would disagree for reasons that are not a change. An edit always moves the modification date.
public struct AssetSnapshot: Sendable, Equatable {
    public let modificationDate: Date?
    public let isFavorite: Bool

    public init(modificationDate: Date?, isFavorite: Bool) {
        self.modificationDate = modificationDate
        self.isFavorite = isFavorite
    }
}

/// The second line of defence when the user deletes: the library observer drops changed photos
/// asynchronously, this compares again at the moment of deletion.
public enum DeletionGate {
    public struct Outcome: Sendable, Equatable {
        /// Unchanged since the scan: safe to hand to PhotoKit.
        public let allowed: Set<String>
        /// Changed (or impossible to verify): kept, and dropped from the results.
        public let changed: Set<String>
    }

    /// A photo missing from `current` is already gone: neither allowed nor changed.
    /// A photo with no scanned state, or none with a modification date, cannot be verified and counts as changed.
    public static func partition(
        requested: Set<String>, scanned: [String: AssetSnapshot], current: [String: AssetSnapshot]
    ) -> Outcome {
        var allowed = Set<String>()
        var changed = Set<String>()
        for id in requested {
            guard let now = current[id] else { continue }
            if let before = scanned[id], before.modificationDate != nil, before == now {
                allowed.insert(id)
            } else {
                changed.insert(id)
            }
        }
        return Outcome(allowed: allowed, changed: changed)
    }
}

extension ScanResult {
    /// What every shown item looked like at scan time.
    public var snapshots: [String: AssetSnapshot] {
        var snapshots: [String: AssetSnapshot] = [:]
        for category in CleanupCategory.allCases {
            for item in items(in: category) {
                snapshots[item.id] = AssetSnapshot(modificationDate: item.modificationDate, isFavorite: item.isFavorite)
            }
        }
        return snapshots
    }
}
