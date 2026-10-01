import Foundation
import Testing
@testable import CleanupCore

@Suite struct KeeperTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func item(
        _ id: String, seconds: TimeInterval = 0, bytes: Int64 = 3_000_000, still: Int64? = nil,
        sharpness: Double? = nil, faces: FaceSummary? = nil, favorite: Bool = false, edited: Bool = false,
        pixels: Int = 12_000_000
    ) -> GroupingItem {
        GroupingItem(
            id: id, creationDate: start.addingTimeInterval(seconds),
            fingerprint: Fingerprint([0] + [Float](repeating: 0, count: 767)),
            isFavorite: favorite, isEdited: edited, pixelCount: pixels, byteSize: bytes,
            stillBytes: still, sharpness: sharpness, faces: faces
        )
    }

    private func group(_ items: [GroupingItem]) -> SimilarityGroup {
        SimilarityGrouper.groups(from: items)[0]
    }

    @Test func largerStillBeyondTheMarginWinsClear() {
        let result = group([item("small", seconds: 0, bytes: 1_000_000), item("big", seconds: 1, bytes: 1_100_000)])
        #expect(result.keeperID == "big")
        #expect(result.keeperReason == .size)
        #expect(result.confidence == .clear)
        #expect(result.suggestedRemovalIDs == ["small"])
        #expect(result.reasonLine == "Best: larger file, more detail (+10%).")
    }

    @Test func sizeGapInsideTheMarginIsACloseCallStillPickedByExactBytes() {
        let result = group([item("a", seconds: 0, bytes: 1_000_000), item("b", seconds: 1, bytes: 1_049_000)])
        #expect(result.keeperID == "b")
        #expect(result.keeperReason == .tie)
        #expect(result.confidence == .close)
        #expect(result.suggestedRemovalIDs.isEmpty)
        #expect(result.contenderIDs == ["a"])
        #expect(result.reasonLine.hasPrefix("Close call."))
    }

    @Test func sizeGapJustAboveTheMarginCounts() {
        let result = group([item("a", seconds: 0, bytes: 1_000_000), item("b", seconds: 1, bytes: 1_051_000)])
        #expect(result.confidence == .clear)
        #expect(result.keeperReason == .size)
    }

    @Test func sharpnessVotesWhenSizeAbstains() {
        let result = group([
            item("soft", seconds: 0, bytes: 1_020_000, sharpness: 1.0),
            item("sharp", seconds: 1, bytes: 1_000_000, sharpness: 1.2),
        ])
        #expect(result.keeperID == "sharp")
        #expect(result.keeperReason == .sharpness)
        #expect(result.confidence == .clear)
        #expect(result.reasonLine == "Best: sharper (+20%).")
    }

    @Test func sharpnessGapInsideTheMarginDoesNotVote() {
        let result = group([
            item("a", seconds: 0, bytes: 1_000_000, sharpness: 1.0),
            item("b", seconds: 1, bytes: 1_000_000, sharpness: 1.09),
        ])
        #expect(result.confidence == .close)
        #expect(result.keeperID == "a")
    }

    @Test func sizeAndSharpnessAgreeingGiveOneClearReason() {
        let result = group([
            item("a", seconds: 0, bytes: 1_000_000, sharpness: 1.0),
            item("b", seconds: 1, bytes: 1_350_000, sharpness: 1.5),
        ])
        #expect(result.keeperReason == .sizeAndSharpness)
        #expect(result.confidence == .clear)
        #expect(result.reasonLine == "Best: sharper, larger file (+35%).")
    }

    @Test func splitVoteKeepsTheSizeWinnerAndIsClose() {
        let result = group([
            item("big-soft", seconds: 0, bytes: 2_000_000, sharpness: 1.0),
            item("small-sharp", seconds: 1, bytes: 1_000_000, sharpness: 2.0),
        ])
        #expect(result.keeperID == "big-soft")
        #expect(result.keeperReason == .size)
        #expect(result.confidence == .close)
        #expect(result.suggestedRemovalIDs.isEmpty)
    }

    @Test func overlayCopyThatSharpnessContradictsIsFlaggedClose() {
        let result = group([
            item("clean", seconds: 0, bytes: 3_000_000, sharpness: 1.0),
            item("sticker", seconds: 1, bytes: 3_300_000, sharpness: 0.8),
        ])
        #expect(result.confidence == .close)
        #expect(result.suggestedRemovalIDs.isEmpty)
    }

    @Test func stillBytesBeatTheAssetTotal() {
        let result = group([
            item("live", seconds: 0, bytes: 9_000_000, still: 2_000_000),
            item("plain", seconds: 1, bytes: 3_000_000, still: 3_000_000),
        ])
        #expect(result.keeperID == "plain")
        #expect(result.confidence == .clear)
    }

    @Test func missingStillBytesFallBackToTheAssetTotal() {
        let result = group([
            item("a", seconds: 0, bytes: 1_000_000, still: nil),
            item("b", seconds: 1, bytes: 2_000_000, still: nil),
        ])
        #expect(result.keeperID == "b")
    }

    @Test func zeroStillBytesFallBackToTheAssetTotal() {
        let result = group([
            item("a", seconds: 0, bytes: 1_000_000, still: 0),
            item("b", seconds: 1, bytes: 2_000_000, still: 0),
        ])
        #expect(result.keeperID == "b")
        #expect(result.keeperReason == .size)
    }

    @Test func fewerClosedEyesWinsBeforeSize() {
        let result = group([
            item("blink", seconds: 0, bytes: 3_000_000, faces: FaceSummary(count: 2, closedEyes: 1)),
            item("open", seconds: 1, bytes: 2_000_000, faces: FaceSummary(count: 2, closedEyes: 0)),
        ])
        #expect(result.keeperID == "open")
        #expect(result.keeperReason == .eyes)
        #expect(result.confidence == .close)
        #expect(result.suggestedRemovalIDs.isEmpty)
    }

    @Test func eyesAndSizeAgreeingIsClear() {
        let result = group([
            item("blink", seconds: 0, bytes: 1_000_000, faces: FaceSummary(count: 1, closedEyes: 1)),
            item("open", seconds: 1, bytes: 2_000_000, faces: FaceSummary(count: 1, closedEyes: 0)),
        ])
        #expect(result.confidence == .clear)
        #expect(result.reasonLine == "Best: eyes open. 1 other has closed eyes.")
    }

    @Test func eyesAreIgnoredWhenFaceCountsDifferOrAreMissing() {
        let different = group([
            item("a", seconds: 0, bytes: 1_000_000, faces: FaceSummary(count: 1, closedEyes: 1)),
            item("b", seconds: 1, bytes: 2_000_000, faces: FaceSummary(count: 2, closedEyes: 0)),
        ])
        #expect(different.keeperReason == .size)
        let missing = group([
            item("a", seconds: 0, bytes: 1_000_000, faces: FaceSummary(count: 1, closedEyes: 1)),
            item("b", seconds: 1, bytes: 2_000_000),
        ])
        #expect(missing.keeperReason == .size)
    }

    @Test func favouriteEditedAndResolutionStayClearAndAhead() {
        #expect(group([item("a", seconds: 0, bytes: 9_000_000), item("fav", seconds: 1, bytes: 1_000_000, favorite: true)]).keeperReason == .favourite)
        #expect(group([item("a", seconds: 0, bytes: 9_000_000), item("ed", seconds: 1, bytes: 1_000_000, edited: true)]).keeperReason == .edited)
        let resolution = group([item("a", seconds: 0, bytes: 9_000_000, pixels: 8_000_000), item("b", seconds: 1, bytes: 1_000_000)])
        #expect(resolution.keeperReason == .resolution)
        #expect(resolution.confidence == .clear)
        #expect(resolution.reasonLine == "Best: more pixels (12 MP, the others 8 MP).")
    }

    @Test func equalEverythingIsACloseCallWithTheEarliestPhoto() {
        let result = group([item("later", seconds: 5), item("earlier", seconds: 0)])
        #expect(result.keeperID == "earlier")
        #expect(result.confidence == .close)
    }

    @Test func oneContenderMakesTheWholeGroupClose() {
        let result = group([
            item("best", seconds: 0, bytes: 3_000_000),
            item("clear-loser", seconds: 1, bytes: 1_000_000),
            item("contender", seconds: 2, bytes: 2_950_000),
        ])
        #expect(result.keeperID == "best")
        #expect(result.contenderIDs == ["contender"])
        #expect(result.suggestedRemovalIDs.isEmpty)
    }

    @Test func keeperDoesNotDependOnInputOrder() {
        var items = (0..<8).map { index in
            item("p\(index)", seconds: Double(index), bytes: 1_000_000 + Int64(index * 37_000),
                 sharpness: 1.0 + Double(index % 3) * 0.07)
        }
        let expected = SimilarityGrouper.groups(from: items)[0]
        for seed in 0..<5 {
            items = items.enumerated().sorted { ($0.offset * 7 + seed) % 5 < ($1.offset * 7 + seed) % 5 }.map(\.element)
            let shuffled = SimilarityGrouper.groups(from: items)[0]
            #expect(shuffled.keeperID == expected.keeperID)
            #expect(shuffled.rankedMemberIDs == expected.rankedMemberIDs)
            #expect(shuffled.confidence == expected.confidence)
        }
    }

    @Test func noMemberBeatsTheKeeperOutright() {
        let policy = KeeperPolicy()
        for seed in 0..<50 {
            var generator = SeededGenerator(seed: UInt64(seed))
            let members = (0..<6).map { index in
                item("p\(index)", seconds: Double(index), bytes: Int64.random(in: 900_000...1_200_000, using: &generator),
                     sharpness: Double.random(in: 0.8...1.3, using: &generator))
            }
            let keeper = SimilarityGrouper.keeper(of: members)
            for other in members where other.id != keeper.id {
                #expect(policy.verdict(other, keeper).winner <= 0)
            }
        }
    }

    @Test func zeroByteMembersNeverCrashTheReasonLine() {
        let resolution = group([item("a", seconds: 0, bytes: 0, pixels: 8_000_000), item("b", seconds: 1, bytes: 3_000_000)])
        #expect(resolution.reasonLine == "Best: more pixels (12 MP, the others 8 MP).")
        let favourite = group([item("a", seconds: 0, bytes: 0), item("b", seconds: 1, bytes: 3_000_000, favorite: true)])
        #expect(favourite.keeperReason == .favourite)
        let edited = group([item("a", seconds: 0, bytes: 0), item("b", seconds: 1, bytes: 3_000_000, edited: true)])
        #expect(edited.keeperReason == .edited)
        let bothZero = group([item("a", seconds: 0, bytes: 0), item("b", seconds: 1, bytes: 0)])
        #expect(bothZero.confidence == .close)
        let stillZero = group([item("a", seconds: 0, bytes: 0, still: 0), item("b", seconds: 1, bytes: 3_000_000)])
        #expect(stillZero.keeperID == "b")
        #expect(stillZero.confidence == .close)
    }

    @Test func zeroOrOddSharpnessGivesAPlainLine() {
        let zero = group([
            item("a", seconds: 0, bytes: 1_000_000, sharpness: 0),
            item("b", seconds: 1, bytes: 1_000_000, sharpness: 2.0),
        ])
        #expect(zero.confidence == .close)
        let nan = group([
            item("a", seconds: 0, bytes: 1_000_000, sharpness: .nan),
            item("b", seconds: 1, bytes: 2_000_000, sharpness: .infinity),
        ])
        #expect(nan.keeperID == "b")
        let huge = group([
            item("a", seconds: 0, bytes: 1_000_000, sharpness: 1e-300),
            item("b", seconds: 1, bytes: 1_000_000, sharpness: 1e300),
        ])
        #expect(huge.keeperReason == .sharpness)
        #expect(huge.reasonLine == "Best: sharper.")
    }

    @Test func aTieOnlyAgainstProtectedPhotosIsNotACloseCall() {
        let result = group([item("fav", seconds: 0, favorite: true), item("fav2", seconds: 1, favorite: true)])
        #expect(result.confidence == .clear)
        #expect(result.keeperReason == .favourite)
        #expect(!result.reasonLine.contains("Close call"))
        let edited = group([item("e1", seconds: 0, edited: true), item("e2", seconds: 1, edited: true)])
        #expect(edited.reasonLine == "Best: you edited it.")
    }
}
