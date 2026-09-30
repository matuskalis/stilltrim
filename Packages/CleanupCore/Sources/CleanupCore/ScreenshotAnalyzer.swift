import CoreGraphics
import Foundation
import Vision

/// Reads what is on a screenshot with Vision, on the device: the text and where it sits, barcodes, and
/// Vision's own scene labels. Text uses the fast level, the accurate one took over a minute to prepare
/// its model the first time it ran.
public enum ScreenshotAnalyzer {
    /// Weaker labels are guesses the classifier would not trust anyway.
    private static let minimumLabelConfidence: Float = 0.2

    /// The requests with their revisions pinned, so an OS update that changes Vision's defaults cannot
    /// change what a cached kind meant. All three exist at the iOS 17 floor. Raise
    /// `ScreenshotClassifier.version` when a pin changes.
    static func makeRequests() -> (text: VNRecognizeTextRequest, scene: VNClassifyImageRequest, barcodes: VNDetectBarcodesRequest) {
        let text = VNRecognizeTextRequest()
        text.revision = VNRecognizeTextRequestRevision3
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false
        let scene = VNClassifyImageRequest()
        scene.revision = VNClassifyImageRequestRevision2
        let barcodes = VNDetectBarcodesRequest()
        barcodes.revision = VNDetectBarcodesRequestRevision4
        return (text, scene, barcodes)
    }

    /// Throws when Vision cannot run, so a broken request is never mistaken for an empty screenshot.
    public static func features(of image: CGImage) throws -> ScreenshotFeatures {
        let (text, scene, barcodes) = makeRequests()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([text, scene, barcodes])

        let lines = (text.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            // Vision measures from the bottom left, the classifier from the top left.
            return RecognizedLine(
                text: candidate.string, minX: box.minX, maxX: box.maxX, minY: 1 - box.maxY, maxY: 1 - box.minY
            )
        }
        var labels: [String: Double] = [:]
        for label in scene.results ?? [] where label.confidence >= minimumLabelConfidence {
            labels[label.identifier] = Double(label.confidence)
        }
        return ScreenshotFeatures(lines: lines, barcodeCount: barcodes.results?.count ?? 0, labels: labels)
    }

    public static func kind(of image: CGImage) throws -> ScreenshotKind {
        ScreenshotClassifier.classify(try features(of: image))
    }
}
