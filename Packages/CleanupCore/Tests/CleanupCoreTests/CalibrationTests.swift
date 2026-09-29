import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CleanupCore

/// Checks the shipped thresholds against real photographs. The photos are not committed:
/// run `scripts/fetch-fixtures.sh`, then `CLEANUP_FIXTURES=$PWD/.fixtures swift test`.
///
/// Measured 29 Sep 2026 on 16 photographs (1600 px), Vision revision 2, 256 px long side:
///   different scenes            120 pairs  min 0.720  p10 0.891  median 1.122
///   jpeg q0.4                    16 pairs  max 0.182
///   crop 95% centre              16 pairs  max 0.200
///   crop 90% shifted             16 pairs  max 0.442
///   crop 80% shifted             16 pairs  max 0.424
///   exposure +0.4 EV / -0.6 EV   32 pairs  max 0.240
/// Sharpness at 512 px long side, fine-to-coarse ratio:
///   sharp originals            min 0.368  median 0.674
///   simulator stock photos     0.373 to 0.627, plus one soft-focus leaf photo at 0.236
///   blur sigma 1.5             median 0.321  max 0.448   (mild, not caught)
///   blur sigma 3               max 0.181                 (all caught)
/// The threshold sits at 0.21, between the blur and the soft-focus photo. Flagged photos are only
/// listed for review, never pre-selected, so a miss costs less than a false alarm.
private enum Fixtures {
    static let photos: [CGImage] = {
        guard let path = ProcessInfo.processInfo.environment["CLEANUP_FIXTURES"],
              let names = try? FileManager.default.contentsOfDirectory(atPath: path)
        else { return [] }
        return names.filter { $0.hasSuffix(".jpg") }.sorted().compactMap { name in
            CGImageSourceCreateWithURL(URL(fileURLWithPath: path + "/" + name) as CFURL, nil)
                .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        }
    }()
}

@Suite(.enabled(if: Fixtures.photos.count >= 8, "set CLEANUP_FIXTURES to a folder of photos"))
struct CalibrationTests {
    private let rules = SimilarityRules()

    @Test func visionSeparatesSameSceneVariantsFromOtherScenes() throws {
        let fingerprinter = VisionFingerprinter()
        let photos = Fixtures.photos
        func print256(_ image: CGImage) throws -> Fingerprint {
            try fingerprinter.fingerprint(of: Synthetic.resized(image, longSide: 256))
        }
        let base = try photos.map(print256)

        var different: [Float] = []
        for i in base.indices { for j in base.indices where j > i { different.append(base[i].distance(to: base[j])) } }
        #expect((different.min() ?? 0) > rules.maxDistance + 0.2)

        let variants: [(CGImage) -> CGImage] = [
            { Synthetic.jpeg($0, quality: 0.4) },
            { Synthetic.cropped($0, fraction: 0.95) },
            { Synthetic.cropped($0, fraction: 0.9, dx: 1, dy: 1) },
            { Synthetic.cropped($0, fraction: 0.8, dx: -1, dy: 1) },
            { Synthetic.exposure($0, ev: 0.4) },
            { Synthetic.exposure($0, ev: -0.6) },
        ]
        var same: [Float] = []
        for make in variants {
            for (index, photo) in photos.enumerated() {
                same.append(try base[index].distance(to: print256(make(photo))))
            }
        }
        let inside = same.filter { $0 <= rules.maxDistance }.count
        print("calibration: different min \(different.min()!), variants within threshold \(inside)/\(same.count), max \(same.max()!)")
        #expect(Double(inside) / Double(same.count) >= 0.95)
    }

    @Test func fileSizeKeepsTheOriginalOverDegradedCopies() throws {
        func candidate(_ id: String, _ image: CGImage, quality: Double) -> GroupingItem {
            GroupingItem(
                id: id, creationDate: .distantPast, fingerprint: Fingerprint([0]), isFavorite: false, isEdited: false,
                pixelCount: image.width * image.height, byteSize: Int64(Synthetic.jpegData(image, quality: quality).count)
            )
        }
        for photo in Fixtures.photos {
            let copies = [
                candidate("original", photo, quality: 0.9),
                candidate("recompressed", photo, quality: 0.4),
                candidate("cropped", Synthetic.cropped(photo, fraction: 0.9), quality: 0.9),
                candidate("half", Synthetic.resized(photo, longSide: photo.width / 2), quality: 0.9),
                candidate("blurred", Synthetic.blurred(photo, sigma: 1.5), quality: 0.9),
            ]
            #expect(SimilarityGrouper.keeper(of: copies).id == "original")
        }
    }

    @Test func realPhotosAreNotFlaggedAndBlurredOnesAre() throws {
        let thresholds = QualityThresholds.standard
        var sharpFlagged: [QualityIssue] = []
        var blurred3Missed = 0
        var blurred15Caught = 0
        for photo in Fixtures.photos {
            let sharp = try #require(ImageAnalyzer.measure(photo))
            if let issue = thresholds.issue(for: sharp) { sharpFlagged.append(issue) }
            let heavy = try #require(ImageAnalyzer.measure(Synthetic.blurred(photo, sigma: 3)))
            if thresholds.issue(for: heavy) != .blurry { blurred3Missed += 1 }
            let mild = try #require(ImageAnalyzer.measure(Synthetic.blurred(photo, sigma: 1.5)))
            if thresholds.issue(for: mild) == .blurry { blurred15Caught += 1 }
        }
        print("calibration: sharp flagged \(sharpFlagged.count)/\(Fixtures.photos.count), sigma3 missed \(blurred3Missed), sigma1.5 caught \(blurred15Caught)")
        #expect(sharpFlagged.isEmpty)
        #expect(blurred3Missed == 0)
    }
}
