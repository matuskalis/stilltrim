import Foundation
import Testing
@testable import CleanupCore

@Suite struct ScanResultTests {
    private func item(_ id: String, bytes: Int64 = 1_000, keeper: Bool = false) -> CleanupItem {
        CleanupItem(id: id, byteSize: bytes, creationDate: .distantPast, isKeeper: keeper)
    }

    /// Group of four, ranked best to worst as k, a, b, c. `k` is the best photo; `fav` is never suggested.
    private func group(_ prefix: String = "") -> SimilarGroup {
        SimilarGroup(
            id: prefix + "k",
            items: [item(prefix + "k", bytes: 4_000, keeper: true), item(prefix + "a", bytes: 3_000),
                    item(prefix + "b", bytes: 2_000), item(prefix + "c", bytes: 1_000)],
            suggestedRemovalIDs: [prefix + "a", prefix + "b", prefix + "c"],
            rankedIDs: [prefix + "k", prefix + "a", prefix + "b", prefix + "c"]
        )
    }

    private var result: ScanResult {
        ScanResult(
            screenshots: [item("s1", bytes: 100), item("s2", bytes: 200)],
            similarGroups: [group()],
            lowQuality: [item("q1", bytes: 300)],
            bigVideos: [item("v1", bytes: 900)]
        )
    }

    @Test func removingScreenshotsLeavesEveryOtherCategoryAlone() {
        let after = result.removing(ids: ["s1"])
        #expect(after.screenshots.map(\.id) == ["s2"])
        #expect(after.lowQuality.map(\.id) == ["q1"])
        #expect(after.bigVideos.map(\.id) == ["v1"])
        #expect(after.similarGroups.count == 1)
    }

    @Test func removingANonBestPhotoKeepsTheGroupAndItsBestPhoto() throws {
        let after = result.removing(ids: ["b"])
        let remaining = try #require(after.similarGroups.first)
        #expect(remaining.items.map(\.id) == ["k", "a", "c"])
        #expect(remaining.items.first(where: \.isKeeper)?.id == "k")
        #expect(remaining.suggestedRemovalIDs == ["a", "c"])
    }

    @Test func removingTheBestPhotoPromotesTheNextRankedOneAndStopsSuggestingIt() throws {
        let after = result.removing(ids: ["k"])
        let remaining = try #require(after.similarGroups.first)
        #expect(remaining.items.map(\.id) == ["a", "b", "c"])
        #expect(remaining.items.first(where: \.isKeeper)?.id == "a")
        #expect(remaining.suggestedRemovalIDs == ["b", "c"])
        #expect(remaining.id == "k", "the group keeps its identity")
    }

    @Test func aGroupDownToOnePhotoDisappears() {
        #expect(result.removing(ids: ["a", "b", "c"]).similarGroups.isEmpty)
        #expect(result.removing(ids: ["k", "a", "b"]).similarGroups.isEmpty)
    }

    @Test func removingEveryIdEmptiesTheResult() {
        let ids = result.allIDs
        let after = result.removing(ids: ids)
        #expect(after.allIDs.isEmpty)
        #expect(after.totalReclaimableBytes == 0)
    }

    @Test func aGroupReclaimsEverythingExceptItsBestPhoto() {
        #expect(group().reclaimableBytes == 6_000)
        #expect(group().removableCount == 3)
        #expect(result.reclaimableBytes(in: .similar) == 6_000)
        #expect(result.removableCount(in: .similar) == 3)
    }

    @Test func totalCountsEachCategoryOnce() {
        #expect(result.totalReclaimableBytes == 100 + 200 + 6_000 + 300 + 900)
    }

    @Test func byteSizeOfIdsCountsEachPhotoOnceAndIgnoresUnknownIds() {
        #expect(result.byteSize(of: ["s1", "s1", "k", "nope"]) == 100 + 4_000)
    }

    @Test func suggestedSelectionIsTheUnionOverGroupsAndNeverHoldsABestPhoto() {
        let two = ScanResult(similarGroups: [group("x-"), group("y-")])
        #expect(two.suggestedSelection == ["x-a", "x-b", "x-c", "y-a", "y-b", "y-c"])
        #expect(two.suggestedSelection.isDisjoint(with: two.keeperIDs))
        #expect(two.keeperIDs == ["x-k", "y-k"])
    }

    @Test func allIDsCoversEveryCategory() {
        #expect(result.allIDs == ["s1", "s2", "k", "a", "b", "c", "q1", "v1"])
    }

    private func shot(_ id: String, _ kind: ScreenshotKind?, bytes: Int64 = 1_000) -> CleanupItem {
        CleanupItem(id: id, byteSize: bytes, creationDate: .distantPast, screenshotKind: kind)
    }

    @Test func screenshotsAreSectionedByKindBiggestFirstAndMixLast() {
        var sectioned = ScanResult(screenshots: [
            shot("m1", .mix, bytes: 9_000), shot("c1", .chat, bytes: 1_000),
            shot("r1", .receipt, bytes: 5_000), shot("c2", .chat, bytes: 2_000),
        ])
        sectioned.arrangeScreenshots()
        #expect(sectioned.screenshotSections.map(\.kind) == [.receipt, .chat, .mix])
        #expect(sectioned.screenshotSections[1].items.map(\.id) == ["c1", "c2"], "equal dates fall back to the id")
        #expect(sectioned.screenshotSections[1].byteSize == 3_000)
    }

    @Test func aScreenshotWithoutAKindIsMix() {
        #expect(ScanResult(screenshots: [shot("x", nil)]).screenshotSections.map(\.kind) == [.mix])
    }

    @Test func sectionsOfEqualSizeKeepAFixedOrder() {
        var sectioned = ScanResult(screenshots: [shot("w", .web), shot("c", .chat), shot("r", .receipt)])
        sectioned.arrangeScreenshots()
        #expect(sectioned.screenshotSections.map(\.kind) == [.chat, .receipt, .web])
    }

    @Test func screenshotItemsFollowTheOrderOnScreen() {
        var sectioned = ScanResult(screenshots: [shot("m1", .mix), shot("c1", .chat, bytes: 5_000), shot("m2", .mix)])
        sectioned.arrangeScreenshots()
        #expect(sectioned.items(in: .screenshots).map(\.id) == ["c1", "m1", "m2"])
    }

    @Test func newestScreenshotsComeFirstInsideAKind() {
        var sectioned = ScanResult(screenshots: [
            CleanupItem(id: "old", byteSize: 1, creationDate: Date(timeIntervalSince1970: 100), screenshotKind: .chat),
            CleanupItem(id: "new", byteSize: 1, creationDate: Date(timeIntervalSince1970: 900), screenshotKind: .chat),
        ])
        sectioned.arrangeScreenshots()
        #expect(sectioned.screenshotSections[0].items.map(\.id) == ["new", "old"])
    }

    @Test func deletingFromASectionDoesNotReorderTheSections() {
        var sectioned = ScanResult(screenshots: [
            shot("c1", .chat, bytes: 5_000), shot("c2", .chat, bytes: 5_000), shot("r1", .receipt, bytes: 6_000),
        ])
        sectioned.arrangeScreenshots()
        #expect(sectioned.screenshotSections.map(\.kind) == [.chat, .receipt])
        // Chats now hold 5,000 bytes against 6,000 for receipts, and still stand first.
        #expect(sectioned.removing(ids: ["c1"]).screenshotSections.map(\.kind) == [.chat, .receipt])
    }

    @Test func removingAScreenshotDropsItsSectionWhenItWasTheLast() {
        let sectioned = ScanResult(screenshots: [shot("c1", .chat), shot("r1", .receipt)]).removing(ids: ["c1"])
        #expect(sectioned.screenshotSections.map(\.kind) == [.receipt])
    }

    private func protectedItem(_ id: String, favorite: Bool = false, edited: Bool = false, bytes: Int64 = 1_000) -> CleanupItem {
        CleanupItem(id: id, byteSize: bytes, creationDate: .distantPast, isFavorite: favorite, isEdited: edited)
    }

    private var mixedResult: ScanResult {
        ScanResult(
            screenshots: [
                protectedItem("s1"), protectedItem("s2", favorite: true),
                CleanupItem(id: "r1", byteSize: 1_000, creationDate: .distantPast, screenshotKind: .recording, isEdited: true),
                CleanupItem(id: "r2", byteSize: 1_000, creationDate: .distantPast, screenshotKind: .recording),
            ],
            similarGroups: [group()],
            lowQuality: [protectedItem("q1"), protectedItem("q2", edited: true)],
            bigVideos: [protectedItem("v1", favorite: true), protectedItem("v2", favorite: true, edited: true)]
        )
    }

    @Test func anItemIsProtectedWhenFavouriteOrEdited() {
        #expect(!protectedItem("a").isProtected)
        #expect(protectedItem("a", favorite: true).isProtected)
        #expect(protectedItem("a", edited: true).isProtected)
    }

    @Test func bulkSelectionSkipsFavouritesAndEditedPhotosOutsideSimilarGroups() {
        #expect(mixedResult.bulkSelectableIDs(in: .screenshots) == ["s1", "r2"])
        #expect(mixedResult.bulkSelectableIDs(in: .lowQuality) == ["q1"])
        #expect(mixedResult.bulkSelectableIDs(in: .bigVideos).isEmpty)
    }

    @Test func bulkSelectionInSimilarGroupsIsTheSuggestion() {
        #expect(mixedResult.bulkSelectableIDs(in: .similar) == mixedResult.suggestedSelection)
        #expect(mixedResult.protectedCountLeftOut(in: .similar) == 0)
    }

    @Test func protectedItemsLeftOutAreCounted() {
        #expect(mixedResult.protectedCountLeftOut(in: .screenshots) == 2)
        #expect(mixedResult.protectedCountLeftOut(in: .lowQuality) == 1)
        #expect(mixedResult.protectedCountLeftOut(in: .bigVideos) == 2)
    }

    @Test func aScreenshotSectionSkipsProtectedItemsToo() throws {
        let sections = mixedResult.screenshotSections
        let mix = try #require(sections.first { $0.kind == .mix })
        let recordings = try #require(sections.first { $0.kind == .recording })
        #expect(mix.bulkSelectableIDs == ["s1"])
        #expect(mix.protectedCountLeftOut == 1)
        #expect(recordings.bulkSelectableIDs == ["r2"])
        #expect(recordings.protectedCountLeftOut == 1)
    }

    @Test func theToolbarButtonFollowsWhatIsSelectable() {
        let all = mixedResult
        #expect(all.bulkSelectionAction(in: .lowQuality, selection: []) == .select)
        #expect(all.bulkSelectionAction(in: .lowQuality, selection: ["q1"]) == .deselectAll)
        #expect(all.bulkSelectionAction(in: .bigVideos, selection: []) == .none)
        #expect(all.bulkSelectionAction(in: .bigVideos, selection: ["v1"]) == .deselectAll)
        #expect(all.bulkSelectionAction(in: .similar, selection: []) == .select)
        #expect(all.bulkSelectionAction(in: .similar, selection: all.suggestedSelection) == .deselectAll)
        #expect(ScanResult().bulkSelectionAction(in: .screenshots, selection: []) == .none)
    }

    @Test func protectionChangesNeitherTotalsNorSizes() {
        #expect(mixedResult.removableCount(in: .bigVideos) == 2)
        #expect(mixedResult.reclaimableBytes(in: .bigVideos) == 2_000)
        #expect(mixedResult.byteSize(of: ["v1", "v2", "q2"]) == 3_000)
        #expect(mixedResult.screenshotSections.map(\.byteSize).reduce(0, +) == 4_000)
    }
}
