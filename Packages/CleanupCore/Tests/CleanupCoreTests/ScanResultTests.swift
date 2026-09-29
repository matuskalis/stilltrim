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
}
