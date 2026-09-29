import Foundation
import Testing
@testable import CleanupCore

@Suite struct GroupingTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Items sit on one axis, so the distance between two items is the gap between their positions.
    private func item(
        _ id: String, at position: Float, seconds: TimeInterval = 0,
        favorite: Bool = false, edited: Bool = false, bytes: Int64 = 3_000_000, pixels: Int = 12_000_000
    ) -> GroupingItem {
        GroupingItem(
            id: id,
            creationDate: start.addingTimeInterval(seconds),
            fingerprint: Fingerprint([position] + [Float](repeating: 0, count: 767)),
            isFavorite: favorite,
            isEdited: edited,
            pixelCount: pixels,
            byteSize: bytes
        )
    }

    @Test func closeItemsFormOneGroupAndFarItemsStayAlone() {
        let groups = SimilarityGrouper.groups(from: [
            item("a", at: 0, seconds: 0),
            item("b", at: 0.1, seconds: 5),
            item("c", at: 5, seconds: 10),
        ])
        #expect(groups.count == 1)
        #expect(Set(groups[0].memberIDs) == ["a", "b"])
    }

    @Test func chainOfSlowlyDriftingItemsDoesNotMergeTheEnds() {
        let groups = SimilarityGrouper.groups(from: [
            item("a", at: 0, seconds: 0),
            item("b", at: 0.4, seconds: 5),
            item("c", at: 0.8, seconds: 10),
        ])
        #expect(groups.count == 1)
        #expect(Set(groups[0].memberIDs) == ["a", "b"])
    }

    @Test func itemsFarApartInTimeAreNotGrouped() {
        let rules = SimilarityRules()
        let groups = SimilarityGrouper.groups(from: [
            item("a", at: 0, seconds: 0),
            item("b", at: 0, seconds: rules.maxInterval + 1),
        ], rules: rules)
        #expect(groups.isEmpty)
    }

    @Test func itemsBeyondTheNeighbourLimitAreNotGrouped() {
        var rules = SimilarityRules()
        rules.maxNeighbors = 3
        let items = [item("first", at: 0, seconds: 0)]
            + (1...3).map { item("filler\($0)", at: Float($0) * 10, seconds: Double($0)) }
            + [item("twin", at: 0, seconds: 4)]
        #expect(SimilarityGrouper.groups(from: items, rules: rules).isEmpty)
    }

    @Test func inputOrderDoesNotMatter() {
        let groups = SimilarityGrouper.groups(from: [
            item("b", at: 0.1, seconds: 5),
            item("a", at: 0, seconds: 0),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].memberIDs == ["a", "b"])
    }

    @Test func singlesAreNotReturned() {
        #expect(SimilarityGrouper.groups(from: [item("a", at: 0)]).isEmpty)
        #expect(SimilarityGrouper.groups(from: []).isEmpty)
    }

    @Test func keeperIsTheFavouriteBeforeAnythingElse() {
        let groups = SimilarityGrouper.groups(from: [
            item("big", at: 0, seconds: 0, bytes: 9_000_000),
            item("fav", at: 0.05, seconds: 1, favorite: true, bytes: 1_000_000),
            item("edited", at: 0.05, seconds: 2, edited: true, bytes: 5_000_000),
        ])
        #expect(groups[0].keeperID == "fav")
    }

    @Test func keeperIsTheEditedOneWhenNoFavourite() {
        let groups = SimilarityGrouper.groups(from: [
            item("big", at: 0, seconds: 0, bytes: 9_000_000),
            item("edited", at: 0.05, seconds: 2, edited: true, bytes: 1_000_000),
        ])
        #expect(groups[0].keeperID == "edited")
    }

    @Test func keeperIsTheHigherResolutionEvenWithASmallerFile() {
        let groups = SimilarityGrouper.groups(from: [
            item("small-but-heavy", at: 0, seconds: 0, bytes: 5_000_000, pixels: 2_000_000),
            item("full", at: 0.05, seconds: 1, bytes: 2_000_000, pixels: 12_000_000),
        ])
        #expect(groups[0].keeperID == "full")
    }

    @Test func keeperIsTheLargestFileAtEqualResolution() {
        let groups = SimilarityGrouper.groups(from: [
            item("soft", at: 0, seconds: 0, bytes: 1_000_000),
            item("crisp", at: 0.05, seconds: 1, bytes: 3_000_000),
            item("middle", at: 0.05, seconds: 2, bytes: 2_000_000),
        ])
        #expect(groups[0].keeperID == "crisp")
    }

    @Test func rankedMembersRunFromBestToWorstWithTheKeeperFirst() {
        let groups = SimilarityGrouper.groups(from: [
            item("plain-small", at: 0, seconds: 0, bytes: 1_000_000),
            item("plain-big", at: 0.05, seconds: 1, bytes: 4_000_000),
            item("edited", at: 0.05, seconds: 2, edited: true, bytes: 2_000_000),
            item("fav", at: 0.05, seconds: 3, favorite: true, bytes: 1_500_000),
        ])
        #expect(groups[0].rankedMemberIDs == ["fav", "edited", "plain-big", "plain-small"])
        #expect(groups[0].rankedMemberIDs.first == groups[0].keeperID)
    }

    @Test func identicalCandidatesResolveToTheEarliestPhoto() {
        let groups = SimilarityGrouper.groups(from: [
            item("later", at: 0.05, seconds: 5),
            item("earlier", at: 0, seconds: 0),
        ])
        #expect(groups[0].keeperID == "earlier")
    }

    @Test func removalSuggestionsSkipTheKeeperFavouritesAndEditedPhotos() {
        let groups = SimilarityGrouper.groups(from: [
            item("keeper", at: 0, seconds: 0, favorite: true),
            item("edited", at: 0.05, seconds: 1, edited: true),
            item("fav2", at: 0.05, seconds: 2, favorite: true),
            item("plain1", at: 0.05, seconds: 3),
            item("plain2", at: 0.05, seconds: 4),
        ])
        #expect(groups.count == 1)
        #expect(Set(groups[0].suggestedRemovalIDs) == ["plain1", "plain2"])
    }
}
