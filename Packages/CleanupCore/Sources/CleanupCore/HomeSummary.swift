import Foundation

/// What the Home hero says. Decided on items, not bytes: a result of empty files is still not "nothing".
public enum HomeSummary: Equatable, Sendable {
    case nothing
    case bytes(Int64)
    case items(Int)

    public init(itemCount: Int, bytes: Int64) {
        if itemCount <= 0 {
            self = .nothing
        } else if bytes > 0 {
            self = .bytes(bytes)
        } else {
            self = .items(itemCount)
        }
    }

    /// Each category's bar length as a share of the largest category, so the biggest row is full.
    /// A category with bytes never drops below `minimum`; one without bytes gets none.
    public static func barShares(_ bytes: [Int64], minimum: Double = 0.04) -> [Double] {
        let largest = bytes.max() ?? 0
        guard largest > 0 else { return bytes.map { _ in 0 } }
        return bytes.map { $0 > 0 ? max(Double($0) / Double(largest), minimum) : 0 }
    }
}

extension ScanResult {
    public var totalRemovableCount: Int {
        CleanupCategory.allCases.reduce(0) { $0 + removableCount(in: $1) }
    }
}
