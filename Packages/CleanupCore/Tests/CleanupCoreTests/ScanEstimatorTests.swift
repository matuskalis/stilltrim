import Foundation
import Testing
@testable import CleanupCore

@Suite struct ScanEstimatorTests {
    private let plan = ScanWorkPlan(sizing: 1_000, analyzing: 500, reading: 50)

    private func raw(
        _ stage: ScanStage, done: Int = 0, total: Int = 0, seconds: Double = 0, plan: ScanWorkPlan? = nil
    ) -> Double? {
        ScanEstimator.secondsLeft(
            plan: plan ?? self.plan, stage: stage, done: done, total: total, secondsInStage: seconds)
    }

    @Test func noPlanMeansNoEstimate() {
        #expect(ScanEstimator.secondsLeft(plan: nil, stage: .sizing, done: 5, total: 100, secondsInStage: 1) == nil)
    }

    @Test func priorsAreUsedBeforeEnoughData() throws {
        let left = try #require(raw(.sizing, done: 10, total: 1_000, seconds: 1))
        let expected = 990 * ScanEstimator.sizingSecondsPerItem + 500 * ScanEstimator.analyzingSecondsPerItem
            + 50 * ScanEstimator.readingSecondsPerItem + ScanEstimator.groupingSeconds
        #expect(abs(left - expected) < 1e-9)
    }

    @Test func observedRateReplacesPriorOnceThereIsEnoughData() throws {
        let left = try #require(raw(.sizing, done: 500, total: 1_000, seconds: 5))
        let expected = 500 * (5.0 / 500) + 500 * ScanEstimator.analyzingSecondsPerItem
            + 50 * ScanEstimator.readingSecondsPerItem + ScanEstimator.groupingSeconds
        #expect(abs(left - expected) < 1e-9)
    }

    @Test func enoughDataMeansThirtyItemsOrThreeSeconds() throws {
        let later = 500 * 0.008 + 50 * 0.08 + 1.0
        let fewItems = try #require(raw(.sizing, done: 30, total: 1_000, seconds: 0.3))
        let fewSeconds = try #require(raw(.sizing, done: 5, total: 1_000, seconds: 3))
        let tooLittle = try #require(raw(.sizing, done: 5, total: 1_000, seconds: 0.5))
        #expect(abs(fewItems - (970 * 0.01 + later)) < 1e-6)
        #expect(abs(fewSeconds - (995 * 0.6 + later)) < 1e-6)
        #expect(abs(tooLittle - (995 * 0.005 + later)) < 1e-6)
    }

    @Test func slowStageRaisesTheEstimate() throws {
        let fast = try #require(raw(.analyzing, done: 100, total: 500, seconds: 0.4))
        let slow = try #require(raw(.analyzing, done: 100, total: 500, seconds: 4))
        #expect(slow > fast)
    }

    @Test func analysingCountsOnlyPendingItemsWhenSomeWereCached() throws {
        let cachedPlan = ScanWorkPlan(sizing: 0, analyzing: 100, reading: 0)
        let atStart = try #require(raw(.analyzing, done: 900, total: 1_000, seconds: 0, plan: cachedPlan))
        #expect(abs(atStart - (100 * ScanEstimator.analyzingSecondsPerItem + ScanEstimator.groupingSeconds)) < 1e-9)
        let half = try #require(raw(.analyzing, done: 950, total: 1_000, seconds: 5, plan: cachedPlan))
        #expect(abs(half - (50 * 0.1 + ScanEstimator.groupingSeconds)) < 1e-9)
    }

    @Test func steadyProgressGivesADecreasingEstimate() throws {
        var last = Double.infinity
        for step in 0...10 {
            let value = try #require(raw(.sizing, done: step * 100, total: 1_000, seconds: Double(step) * 0.5))
            #expect(value <= last + 1e-9)
            last = value
        }
    }

    @Test func warmCacheIsAlmostDoneImmediately() throws {
        let warm = ScanWorkPlan(sizing: 0, analyzing: 0, reading: 0)
        let left = try #require(raw(.listing, plan: warm))
        #expect(left <= ScanEstimator.groupingSeconds + 1e-9)
        #expect(ScanEstimator.text(secondsLeft: left, elapsed: 3) == "Almost done")
    }

    @Test func neverNegative() throws {
        let done = try #require(raw(.grouping, seconds: 50))
        #expect(done == 0)
        let over = try #require(raw(.reading, done: 80, total: 50, seconds: 10))
        #expect(over >= 0)
    }

    @Test func textBoundaries() {
        #expect(ScanEstimator.text(secondsLeft: nil, elapsed: 20) == "Estimating the time left")
        #expect(ScanEstimator.text(secondsLeft: 500, elapsed: 2.9) == "Estimating the time left")
        #expect(ScanEstimator.text(secondsLeft: 500, elapsed: 3) == "About 8 min left")
        #expect(ScanEstimator.text(secondsLeft: 9.9, elapsed: 5) == "Almost done")
        #expect(ScanEstimator.text(secondsLeft: 10, elapsed: 5) == "Less than a minute left")
        #expect(ScanEstimator.text(secondsLeft: 59.9, elapsed: 5) == "Less than a minute left")
        #expect(ScanEstimator.text(secondsLeft: 60, elapsed: 5) == "About 1 min left")
        #expect(ScanEstimator.text(secondsLeft: 20 * 60, elapsed: 5) == "About 20 min left")
        #expect(ScanEstimator.text(secondsLeft: 22 * 60, elapsed: 5) == "About 20 min left")
        #expect(ScanEstimator.text(secondsLeft: 23 * 60, elapsed: 5) == "About 25 min left")
        #expect(ScanEstimator.text(secondsLeft: 47 * 60, elapsed: 5) == "About 45 min left")
    }

    @Test func smoothingLimitsHowFastTheValueRises() throws {
        var smoother = ScanTimeLeft()
        #expect(smoother.update(raw: 100, elapsed: 3) == 100)
        let first = smoother.update(raw: 120, elapsed: 4)
        var value = try #require(first)
        #expect(value <= 100 - 1 + ScanTimeLeft.maxRisePerSecond + 1e-9)
        for second in 5...100 {
            let updated = smoother.update(raw: 120, elapsed: Double(second))
            let next = try #require(updated)
            #expect(next - value <= ScanTimeLeft.maxRisePerSecond - 1 + 1e-9)
            value = next
        }
        #expect(value == 120)
    }

    @Test func smoothingFollowsFallsAndStaysNonNegative() {
        var smoother = ScanTimeLeft()
        _ = smoother.update(raw: 100, elapsed: 3)
        #expect(smoother.update(raw: 40, elapsed: 4) == 40)
        #expect(smoother.update(raw: 0, elapsed: 5) == 0)
        #expect(smoother.update(raw: -3, elapsed: 9) == 0)
    }

    @Test func smoothingStaysNilWithoutAnEstimate() {
        var smoother = ScanTimeLeft()
        #expect(smoother.update(raw: nil, elapsed: 1) == nil)
    }
}
