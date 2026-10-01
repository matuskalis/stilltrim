import Foundation

/// What a finger swipe across a photo grid has selected at one moment. Every photo from the one the drag
/// started on to the one under the finger now, in display order and in either direction, is set to the
/// mode. Everything else stays as it was when the drag began, so moving the finger back undoes photos.
/// Ids that are not in `order` are never added or removed.
public struct DragSelection: Sendable {
    public enum Mode: Sendable {
        case select, deselect
    }

    public let mode: Mode
    private let indexOf: [String: Int]
    private let order: [String]
    private let startSelection: Set<String>
    private let anchorIndex: Int?

    /// `mode` defaults to what the first photo calls for: a selected one starts deselecting, an unselected one selecting.
    public init(order: [String], startSelection: Set<String>, anchor: String, mode: Mode? = nil) {
        self.order = order
        self.startSelection = startSelection
        self.mode = mode ?? (startSelection.contains(anchor) ? .deselect : .select)
        indexOf = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        anchorIndex = indexOf[anchor]
    }

    public func selection(through current: String) -> Set<String> {
        guard let anchorIndex, let currentIndex = indexOf[current] else { return startSelection }
        let run = order[min(anchorIndex, currentIndex)...max(anchorIndex, currentIndex)]
        switch mode {
        case .select: return startSelection.union(run)
        case .deselect: return startSelection.subtracting(run)
        }
    }
}
