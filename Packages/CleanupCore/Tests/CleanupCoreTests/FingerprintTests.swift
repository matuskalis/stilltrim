import Foundation
import Testing
import Vision
@testable import CleanupCore

@Suite struct FingerprintTests {
    @Test func distanceToSelfIsZeroAndSymmetric() {
        let a = Fingerprint((0..<768).map { Float($0 % 7) / 7 })
        let b = Fingerprint((0..<768).map { Float($0 % 5) / 5 })
        #expect(a.distance(to: a) == 0)
        #expect(a.distance(to: b) == b.distance(to: a))
    }

    @Test func halfPrecisionStorageKeepsDistancesWithinATenthOfAThreshold() {
        var rng = SeededGenerator(seed: 3)
        let floatsA = (0..<768).map { _ in Float.random(in: -0.06...0.06, using: &rng) }
        let floatsB = (0..<768).map { _ in Float.random(in: -0.06...0.06, using: &rng) }
        var exact: Float = 0
        for index in 0..<768 { exact += (floatsA[index] - floatsB[index]) * (floatsA[index] - floatsB[index]) }
        let stored = Fingerprint(floatsA).distance(to: Fingerprint(floatsB))
        #expect(abs(stored - exact.squareRoot()) < 0.045)
    }

    @Test func dataRoundTripKeepsEveryValue() throws {
        let original = Fingerprint((0..<768).map { Float($0) / 1000 })
        let restored = try #require(Fingerprint(data: original.data))
        #expect(restored == original)
        #expect(Fingerprint(data: Data([1, 2, 3])) == nil)
    }

    @Test func visionFingerprintHasThePinnedShape() throws {
        let fingerprinter = VisionFingerprinter()
        let fingerprint = try fingerprinter.fingerprint(of: Synthetic.scene(seed: 1))
        #expect(fingerprinter.identifier == "vision-feature-print-r2")
        #expect(fingerprint.values.count == 768)
        #expect(fingerprint.values.allSatisfy { $0.isFinite })
    }

    @Test func visionRanksNearDuplicatesCloserThanOtherScenes() throws {
        let fingerprinter = VisionFingerprinter()
        let original = Synthetic.scene(seed: 11)
        let base = try fingerprinter.fingerprint(of: Synthetic.resized(original, longSide: 256))
        let variants = [
            Synthetic.jpeg(original, quality: 0.4),
            Synthetic.cropped(original, fraction: 0.95),
            Synthetic.cropped(original, fraction: 0.9, dx: 1, dy: 1),
        ]
        let other = try fingerprinter.fingerprint(of: Synthetic.resized(Synthetic.scene(seed: 12), longSide: 256))
        let otherDistance = base.distance(to: other)
        for variant in variants {
            let distance = try base.distance(to: fingerprinter.fingerprint(of: Synthetic.resized(variant, longSide: 256)))
            #expect(distance < otherDistance)
        }
    }

    @Test func ourDistanceMatchesVisionsOwn() throws {
        func observation(_ image: CGImage) throws -> VNFeaturePrintObservation {
            let request = VNGenerateImageFeaturePrintRequest()
            request.revision = VNGenerateImageFeaturePrintRequestRevision2
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return try #require(request.results?.first)
        }
        let first = Synthetic.resized(Synthetic.scene(seed: 21), longSide: 256)
        let second = Synthetic.resized(Synthetic.cropped(Synthetic.scene(seed: 21), fraction: 0.9, dx: 1, dy: 1), longSide: 256)
        var visionDistance: Float = 0
        try observation(first).computeDistance(&visionDistance, to: observation(second))
        let fingerprinter = VisionFingerprinter()
        let ours = try fingerprinter.fingerprint(of: first).distance(to: fingerprinter.fingerprint(of: second))
        #expect(abs(ours - visionDistance) < 0.01)
    }

    @Test func tinyFingerprintSeparatesNearDuplicatesFromOtherScenes() throws {
        let fingerprinter = TinyImageFingerprinter()
        let original = Synthetic.scene(seed: 31)
        let base = try fingerprinter.fingerprint(of: original)
        #expect(base.values.count == 768)
        let near = try base.distance(to: fingerprinter.fingerprint(of: Synthetic.jpeg(original, quality: 0.4)))
        let far = try base.distance(to: fingerprinter.fingerprint(of: Synthetic.scene(seed: 32)))
        #expect(near < 0.15)
        #expect(far > 0.6)
    }
}
