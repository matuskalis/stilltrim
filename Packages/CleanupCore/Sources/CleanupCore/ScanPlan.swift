import Foundation

public enum ScanStage: Int, CaseIterable, Sendable {
    case listing, sizing, analyzing, reading, grouping

    /// Share of a cold scan. Sizing is from the simulator measurement (8.8 s of 18.6 s, 2,031 photos);
    /// the rest are placeholders until stage times are logged on a phone.
    public var weight: Double {
        switch self {
        case .listing: 0.03
        case .sizing: 0.45
        case .analyzing: 0.30
        case .reading: 0.12
        case .grouping: 0.10
        }
    }
}

public enum ScanPlan {
    /// One fraction for the whole scan. It never goes backwards: a finished stage counts in full,
    /// a skipped stage is simply passed, and a stage with no total counts as not started.
    public static func overall(stage: ScanStage, done: Int, total: Int) -> Double {
        let before = ScanStage.allCases.filter { $0.rawValue < stage.rawValue }.reduce(0) { $0 + $1.weight }
        let inStage = total > 0 ? min(max(Double(done) / Double(total), 0), 1) : 0
        return min(before + stage.weight * inStage, 1)
    }
}
