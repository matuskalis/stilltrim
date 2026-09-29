import Foundation

/// The scan result together with what the user has selected, and the rules that keep the two
/// consistent. Every change to the result goes through here, so the selection can never hold an id
/// that is not shown, and a best photo is never selected without the user picking it.
public struct ReviewState: Sendable {
    public private(set) var result: ScanResult?
    public private(set) var selection: Set<String> = []
    public private(set) var isScanning = false

    private var shown: Set<String> = []
    private var changedDuringScan: Set<String> = []
    private var everythingChangedDuringScan = false

    public init() {}

    // MARK: Scanning

    public mutating func beginScan() {
        isScanning = true
        changedDuringScan = []
        everythingChangedDuringScan = false
    }

    /// Applies what changed in the library while the scan ran, then pre-selects the suggestions.
    /// Returns false, with no result, when the library changed too much during the scan to trust it.
    @discardableResult
    public mutating func finishScan(with scanned: ScanResult) -> Bool {
        isScanning = false
        guard !everythingChangedDuringScan else {
            apply(nil)
            return false
        }
        let trusted = scanned.removing(ids: changedDuringScan)
        apply(trusted)
        selection = trusted.suggestedSelection
        return true
    }

    /// The scan was cancelled or failed. Earlier results stay.
    public mutating func abortScan() {
        isScanning = false
    }

    // MARK: Library changes

    /// These photos were removed or changed (favourited, edited, hidden) after they were scanned.
    public mutating func libraryChanged(ids: Set<String>) {
        if isScanning { changedDuringScan.formUnion(ids) }
        apply(result?.removing(ids: ids))
    }

    /// PhotoKit could not say what changed, so nothing scanned before can be trusted.
    public mutating func libraryChangedEverywhere() {
        if isScanning {
            everythingChangedDuringScan = true
        } else {
            apply(nil)
        }
    }

    // MARK: Results

    /// Photos were deleted, or kept for good.
    public mutating func remove(ids: Set<String>) {
        apply(result?.removing(ids: ids))
    }

    public mutating func clear() {
        isScanning = false
        apply(nil)
    }

    // MARK: Selection

    public mutating func toggle(_ id: String) {
        guard shown.contains(id) else { return }
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    public mutating func select(_ ids: Set<String>) {
        selection.formUnion(ids.intersection(shown))
    }

    public mutating func deselect(_ ids: Set<String>) {
        selection.subtract(ids)
    }

    public func selectedIDs(in category: CleanupCategory) -> Set<String> {
        guard let result else { return [] }
        return Set(result.items(in: category).map(\.id)).intersection(selection)
    }

    // MARK: Consistency

    private mutating func apply(_ new: ScanResult?) {
        let previousKeepers = result?.keeperIDs ?? []
        result = new
        shown = new?.allIDs ?? []
        selection.formIntersection(shown)
        // A photo promoted to best just now was a suggestion a moment ago. It starts unselected,
        // so one tap on Delete cannot remove the last good copy. Picking a best photo by hand
        // stays possible.
        if let new { selection.subtract(new.keeperIDs.subtracting(previousKeepers)) }
    }
}
