import Foundation
import Testing
@testable import CleanupCore

@Suite struct ReviewStateTests {
    private func item(_ id: String, keeper: Bool = false) -> CleanupItem {
        CleanupItem(id: id, byteSize: 1_000, creationDate: .distantPast, isKeeper: keeper)
    }

    /// Ranked best to worst: k, a, b, c. `k` is the best photo, the rest are suggested for removal.
    private func group(_ prefix: String = "") -> SimilarGroup {
        SimilarGroup(
            id: prefix + "k",
            items: [item(prefix + "k", keeper: true), item(prefix + "a"), item(prefix + "b"), item(prefix + "c")],
            suggestedRemovalIDs: [prefix + "a", prefix + "b", prefix + "c"],
            rankedIDs: [prefix + "k", prefix + "a", prefix + "b", prefix + "c"]
        )
    }

    private var scan: ScanResult {
        ScanResult(screenshots: [item("s1"), item("s2")], similarGroups: [group()], lowQuality: [item("q1")])
    }

    private func finishedState(_ result: ScanResult? = nil) -> ReviewState {
        var state = ReviewState()
        state.beginScan()
        state.finishScan(with: result ?? scan)
        return state
    }

    @Test func aFinishedScanSelectsOnlyTheSuggestions() {
        let state = finishedState()
        #expect(state.selection == ["a", "b", "c"])
        #expect(state.isScanning == false)
    }

    @Test func aBestPhotoPromotedByAnExternalDeletionStartsUnselected() throws {
        var state = finishedState()
        state.libraryChanged(ids: ["k"])
        let group = try #require(state.result?.similarGroups.first)
        #expect(group.keeperID == "a")
        #expect(state.selection == ["b", "c"], "the new best photo must not stay selected")
    }

    @Test func aBestPhotoPromotedByTheUsersOwnDeletionStartsUnselected() throws {
        var state = finishedState()
        state.toggle("k")
        state.remove(ids: ["k", "b"])
        let group = try #require(state.result?.similarGroups.first)
        #expect(group.keeperID == "a")
        #expect(state.selection == ["c"])
    }

    @Test func aBestPhotoPickedByHandStaysSelectedWhenNothingPromotesIt() {
        var state = finishedState(ScanResult(screenshots: [item("s1")], similarGroups: [group("x-"), group("y-")]))
        state.toggle("x-k")
        state.remove(ids: ["y-a"])
        #expect(state.selection.contains("x-k"))
    }

    @Test func selectionNeverHoldsIdsThatAreNotShown() {
        var state = finishedState()
        state.toggle("nope")
        state.select(["nope", "s1"])
        #expect(state.selection == ["a", "b", "c", "s1"])
        state.remove(ids: ["a", "s1"])
        #expect(state.selection == ["b", "c"])
    }

    @Test func deselectingRemovesOnlyTheGivenIds() {
        var state = finishedState()
        state.select(["s1", "s2"])
        state.deselect(["s1", "a"])
        #expect(state.selection == ["b", "c", "s2"])
    }

    @Test func selectedIDsInACategoryAreTheSelectionIntersectedWithIt() {
        var state = finishedState()
        state.select(["s1"])
        #expect(state.selectedIDs(in: .screenshots) == ["s1"])
        #expect(state.selectedIDs(in: .similar) == ["a", "b", "c"])
        #expect(state.selectedIDs(in: .bigVideos).isEmpty)
    }

    @Test func selectedIDsAboveAnItemAreTheSelectedOnesShownBeforeIt() {
        var state = finishedState()
        // On screen the group reads k, a, b, c and the selection is a, b, c.
        let past: Set<String> = ["k", "a", "b", "c"]
        #expect(state.selectedIDs(in: .similar, above: "c", scrolledPast: past) == ["a", "b"])
        #expect(state.selectedIDs(in: .similar, above: "b", scrolledPast: past) == ["a"], "the item itself is not above")
        #expect(state.selectedIDs(in: .similar, above: "a", scrolledPast: past).isEmpty, "only the unselected best photo is above")
        state.deselect(["a"])
        #expect(state.selectedIDs(in: .similar, above: "c", scrolledPast: past) == ["b"])
    }

    @Test func onlyPhotosTheListReportedAsScrolledPastAreAbove() {
        let state = finishedState()
        // A fast flick went over "a" and "b" without the list reporting them: they were never seen.
        #expect(state.selectedIDs(in: .similar, above: "c", scrolledPast: ["k"]).isEmpty)
        #expect(state.selectedIDs(in: .similar, above: "c", scrolledPast: ["a"]) == ["a"])
        #expect(state.selectedIDs(in: .similar, above: "b", scrolledPast: ["a", "c"]) == ["a"], "c is below b")
    }

    @Test func theFirstShownItemAmongSomeIdsFollowsTheOrderOnScreen() {
        let state = finishedState()
        // On screen the group reads k, a, b, c.
        #expect(state.firstShown(in: .similar, among: ["c", "b"]) == "b")
        #expect(state.firstShown(in: .similar, among: ["c", "s1", "k"]) == "k")
        #expect(state.firstShown(in: .similar, among: ["nope", "s1"]) == nil, "s1 is a screenshot, not in this category")
        #expect(state.firstShown(in: .similar, among: []) == nil)
    }

    @Test func nothingIsAboveAnItemThatIsNotShown() {
        let state = finishedState()
        #expect(state.selectedIDs(in: .similar, above: "nope", scrolledPast: ["k", "a", "b", "c"]).isEmpty)
        #expect(state.selectedIDs(in: .screenshots, above: "a", scrolledPast: ["a"]).isEmpty, "a similar photo is not in the screenshots")
    }

    @Test func aboveFollowsTheOrderOfTheSectionsOnScreen() {
        var shots = ScanResult(screenshots: [
            CleanupItem(id: "m1", byteSize: 100, creationDate: .distantPast, screenshotKind: .mix),
            CleanupItem(id: "c1", byteSize: 500, creationDate: .distantPast, screenshotKind: .chat),
        ])
        shots.arrangeScreenshots()
        var state = finishedState(shots)
        state.select(["m1", "c1"])
        // Chats are bigger, so they come first and the mixed one sits below them.
        #expect(state.selectedIDs(in: .screenshots, above: "m1", scrolledPast: ["c1", "m1"]) == ["c1"])
        #expect(state.selectedIDs(in: .screenshots, above: "c1", scrolledPast: ["c1", "m1"]).isEmpty)
    }

    @Test func changesDuringAScanAreAppliedWhenItFinishes() {
        var state = ReviewState()
        state.beginScan()
        state.libraryChanged(ids: ["b", "s1"])
        #expect(state.isScanning)
        let accepted = state.finishScan(with: scan)
        #expect(accepted)
        let ids = state.result?.allIDs ?? []
        #expect(!ids.contains("b") && !ids.contains("s1"))
        #expect(state.selection == ["a", "c"])
    }

    @Test func aFavouriteAddedMidScanIsNotPreSelected() {
        // The scan listed photo "b" as an ordinary photo; the user favourites it in Photos while
        // the scan runs. The change is reported as a change to "b".
        var state = ReviewState()
        state.beginScan()
        state.libraryChanged(ids: ["b"])
        state.finishScan(with: scan)
        #expect(!state.selection.contains("b"))
    }

    @Test func aWholesaleChangeDuringAScanDiscardsItsResult() {
        var state = ReviewState()
        state.beginScan()
        state.libraryChangedEverywhere()
        let accepted = state.finishScan(with: scan)
        #expect(accepted == false)
        #expect(state.result == nil)
        #expect(state.selection.isEmpty)
        #expect(state.isScanning == false)
    }

    @Test func changesFromBeforeAScanDoNotLeakIntoTheNextOne() {
        var state = ReviewState()
        state.beginScan()
        state.libraryChanged(ids: ["b"])
        state.libraryChangedEverywhere()
        state.abortScan()
        state.beginScan()
        let accepted = state.finishScan(with: scan)
        #expect(accepted)
        #expect(state.result?.allIDs.contains("b") == true)
    }

    @Test func aWholesaleChangeOutsideAScanClearsTheResults() {
        var state = finishedState()
        state.libraryChangedEverywhere()
        #expect(state.result == nil)
        #expect(state.selection.isEmpty)
    }

    @Test func anAbortedScanKeepsThePreviousResults() {
        var state = finishedState()
        state.beginScan()
        state.abortScan()
        #expect(state.result != nil)
        #expect(state.isScanning == false)
    }

    @Test func clearingEmptiesEverythingAndStopsScanning() {
        var state = finishedState()
        state.beginScan()
        state.clear()
        #expect(state.result == nil)
        #expect(state.selection.isEmpty)
        #expect(state.isScanning == false)
    }

    @Test func aProtectedItemCanStillBeTickedByHand() {
        let favourite = CleanupItem(id: "f", byteSize: 1_000, creationDate: .distantPast, isFavorite: true)
        let plain = item("p")
        var state = finishedState(ScanResult(lowQuality: [favourite, plain]))
        let ids = state.result?.bulkSelectableIDs(in: .lowQuality) ?? []
        state.select(ids)
        #expect(state.selection == ["p"])
        state.toggle("f")
        #expect(state.selection == ["p", "f"])
        #expect(state.selectedIDs(in: .lowQuality) == ["p", "f"])
    }
}
