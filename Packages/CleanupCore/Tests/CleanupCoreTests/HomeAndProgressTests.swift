import Foundation
import Testing
@testable import CleanupCore

@Suite struct HomeAndProgressTests {
    @Test func overallNeverGoesBackwardsAcrossAColdScan() {
        var last = -1.0
        for stage in ScanStage.allCases {
            for done in 0...10 {
                let value = ScanPlan.overall(stage: stage, done: done, total: 10)
                #expect(value >= last)
                last = value
            }
        }
        #expect(abs(last - 1) < 1e-9)
    }

    @Test func weightsSumToOne() {
        #expect(abs(ScanStage.allCases.reduce(0) { $0 + $1.weight } - 1) < 1e-9)
    }

    @Test func aStageWithoutATotalCountsAsNotStartedAndSkippedStagesJumpForward() {
        #expect(ScanPlan.overall(stage: .listing, done: 0, total: 0) == 0)
        let afterAnalysis = ScanPlan.overall(stage: .analyzing, done: 10, total: 10)
        #expect(ScanPlan.overall(stage: .grouping, done: 0, total: 0) >= afterAnalysis)
        #expect(ScanPlan.overall(stage: .analyzing, done: 99, total: 10) <= ScanPlan.overall(stage: .reading, done: 0, total: 0) + 1e-9)
    }

    @Test func heroWording() {
        #expect(HomeSummary(itemCount: 0, bytes: 0) == .nothing)
        #expect(HomeSummary(itemCount: 3, bytes: 5_000) == .bytes(5_000))
        #expect(HomeSummary(itemCount: 3, bytes: 0) == .items(3))
    }

    @Test func totalRemovableCountSeesItemsEvenWhenBytesAreZero() {
        let empty = CleanupItem(id: "a", byteSize: 0, creationDate: .distantPast)
        let result = ScanResult(screenshots: [empty], similarGroups: [], lowQuality: [], bigVideos: [])
        #expect(result.totalReclaimableBytes == 0)
        #expect(result.totalRemovableCount == 1)
    }

    @Test func barSharesKeepASmallCategoryVisibleAndZeroEmpty() {
        let shares = HomeSummary.barShares([1_000_000, 10, 0, 500_000])
        #expect(shares[0] == 1)
        #expect(shares[1] == 0.04)
        #expect(shares[2] == 0)
        #expect(shares[3] == 0.5)
        #expect(HomeSummary.barShares([0, 0]) == [0, 0])
    }

    @Test func sizeFormat() {
        let us = Locale(identifier: "en_US")
        #expect(ByteFormat.size(0, locale: us) == nil)
        #expect(ByteFormat.size(-5, locale: us) == nil)
        #expect(ByteFormat.size(1_200_000, locale: us) == "1.2\u{00A0}MB")
        #expect(ByteFormat.size(203_000, locale: us) == "203\u{00A0}kB")
        #expect(ByteFormat.size(1_200_000, locale: Locale(identifier: "sk_SK")) == "1,2\u{00A0}MB")
    }
}
