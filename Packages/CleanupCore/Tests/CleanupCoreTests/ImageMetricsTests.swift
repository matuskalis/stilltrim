import Testing
@testable import CleanupCore

@Suite struct ImageMetricsTests {
    private let thresholds = QualityThresholds.standard

    @Test func blurLowersBothDetailMeasures() throws {
        let sharp = Synthetic.scene(seed: 1)
        let mild = try #require(ImageAnalyzer.measure(Synthetic.blurred(sharp, sigma: 3)))
        let heavy = try #require(ImageAnalyzer.measure(Synthetic.blurred(sharp, sigma: 8)))
        let base = try #require(ImageAnalyzer.measure(sharp))
        #expect(base.laplacianVariance > mild.laplacianVariance)
        #expect(mild.laplacianVariance > heavy.laplacianVariance)
        #expect(base.fineToCoarse > mild.fineToCoarse)
        #expect(mild.fineToCoarse > heavy.fineToCoarse)
    }

    @Test func sameContentAtTwoResolutionsMeasuresAlike() throws {
        let big = Synthetic.scene(seed: 2, width: 3200, height: 2132)
        let small = Synthetic.resized(big, longSide: 1200)
        let bigMetrics = try #require(ImageAnalyzer.measure(big))
        let smallMetrics = try #require(ImageAnalyzer.measure(small))
        let relativeGap = abs(bigMetrics.fineToCoarse - smallMetrics.fineToCoarse) / bigMetrics.fineToCoarse
        #expect(relativeGap < 0.25)
    }

    @Test func tinyImagesAreRejected() {
        #expect(ImageAnalyzer.measure(Synthetic.flat(gray: 0.5, width: 4, height: 4)) == nil)
    }

    @Test func blackFrameIsTooDark() throws {
        let metrics = try #require(ImageAnalyzer.measure(Synthetic.flat(gray: 0)))
        #expect(thresholds.issue(for: metrics) == .tooDark)
    }

    @Test func whiteFrameIsBlownOut() throws {
        let metrics = try #require(ImageAnalyzer.measure(Synthetic.flat(gray: 1)))
        #expect(thresholds.issue(for: metrics) == .blownOut)
    }

    @Test func uniformMidGrayWithSensorNoiseIsFlat() throws {
        let metrics = try #require(ImageAnalyzer.measure(Synthetic.flat(gray: 0.45, noise: 0.004)))
        #expect(thresholds.issue(for: metrics) == .flat)
    }

    @Test func nightSceneWithLightsIsNotFlagged() throws {
        let metrics = try #require(ImageAnalyzer.measure(Synthetic.nightWithLights()))
        #expect(thresholds.issue(for: metrics) == nil)
    }

    @Test func sharpSceneIsNotFlagged() throws {
        for seed in 1...5 as ClosedRange<UInt64> {
            let metrics = try #require(ImageAnalyzer.measure(Synthetic.scene(seed: seed)))
            #expect(thresholds.issue(for: metrics) == nil, "seed \(seed)")
        }
    }

    @Test func heavilyBlurredSceneIsBlurry() throws {
        for seed in 1...5 as ClosedRange<UInt64> {
            let blurred = Synthetic.blurred(Synthetic.scene(seed: seed), sigma: 8)
            let metrics = try #require(ImageAnalyzer.measure(blurred))
            #expect(thresholds.issue(for: metrics) == .blurry, "seed \(seed)")
        }
    }
}
