import CoreGraphics

public struct ImageMetrics: Sendable, Equatable, Codable {
    /// Detail energy at the analysis scale. Near zero means a featureless image.
    public var laplacianVariance: Double
    /// Detail energy relative to the same image at half size. Low when the image is blurred.
    public var fineToCoarse: Double
    public var meanLuminance: Double
    public var luminanceStdDev: Double
    /// 1st percentile of luminance.
    public var darkestLuminance: Double
    /// 99th percentile of luminance.
    public var brightestLuminance: Double
}

public enum QualityIssue: String, Sendable, Equatable, Codable {
    case tooDark
    case blownOut
    case flat
    case blurry
}

public struct QualityThresholds: Sendable, Equatable {
    public var tooDarkBrightest: Double
    public var blownOutDarkest: Double
    public var flatStdDev: Double
    public var blurryFineToCoarse: Double
    public var blurryLaplacianVariance: Double

    /// Chosen from the fixture measurements recorded in `CalibrationTests`.
    public static let standard = QualityThresholds(
        tooDarkBrightest: 0.12,
        blownOutDarkest: 0.92,
        flatStdDev: 0.02,
        blurryFineToCoarse: 0.21,
        blurryLaplacianVariance: 0.0003
    )

    /// The most telling problem first: a black frame is "too dark", never "blurry".
    public func issue(for metrics: ImageMetrics) -> QualityIssue? {
        if metrics.brightestLuminance < tooDarkBrightest { return .tooDark }
        if metrics.darkestLuminance > blownOutDarkest { return .blownOut }
        if metrics.luminanceStdDev < flatStdDev { return .flat }
        if metrics.fineToCoarse < blurryFineToCoarse || metrics.laplacianVariance < blurryLaplacianVariance {
            return .blurry
        }
        return nil
    }
}

public enum ImageAnalyzer {
    public static let analysisLongSide = 512
    private static let minimumSide = 8

    /// Returns nil when the image is too small to measure.
    public static func measure(_ image: CGImage) -> ImageMetrics? {
        guard let gray = GrayBitmap(image, longSide: analysisLongSide) else { return nil }
        let luminance = gray.luminanceStatistics()
        let fine = gray.laplacianVariance()
        let coarse = gray.halved()?.laplacianVariance() ?? 0
        return ImageMetrics(
            laplacianVariance: fine,
            fineToCoarse: fine / max(coarse, 1e-9),
            meanLuminance: luminance.mean,
            luminanceStdDev: luminance.standardDeviation,
            darkestLuminance: luminance.p1,
            brightestLuminance: luminance.p99
        )
    }

    struct GrayBitmap {
        let pixels: [Float]
        let width: Int
        let height: Int

        init?(_ image: CGImage, longSide: Int) {
            let scale = min(1, Double(longSide) / Double(max(image.width, image.height)))
            let width = Int((Double(image.width) * scale).rounded())
            let height = Int((Double(image.height) * scale).rounded())
            guard width >= ImageAnalyzer.minimumSide, height >= ImageAnalyzer.minimumSide else { return nil }
            var bytes = [UInt8](repeating: 0, count: width * height)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                ) else { return false }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            self.pixels = bytes.map { Float($0) / 255 }
            self.width = width
            self.height = height
        }

        private init(pixels: [Float], width: Int, height: Int) {
            self.pixels = pixels
            self.width = width
            self.height = height
        }

        func halved() -> GrayBitmap? {
            let halfWidth = width / 2, halfHeight = height / 2
            guard halfWidth >= 3, halfHeight >= 3 else { return nil }
            var out = [Float](repeating: 0, count: halfWidth * halfHeight)
            for y in 0..<halfHeight {
                for x in 0..<halfWidth {
                    let i = 2 * y * width + 2 * x
                    out[y * halfWidth + x] = (pixels[i] + pixels[i + 1] + pixels[i + width] + pixels[i + width + 1]) / 4
                }
            }
            return GrayBitmap(pixels: out, width: halfWidth, height: halfHeight)
        }

        func laplacianVariance() -> Double {
            var sum = 0.0, sumOfSquares = 0.0, count = 0.0
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let i = y * width + x
                    let response = Double(pixels[i - 1] + pixels[i + 1] + pixels[i - width] + pixels[i + width] - 4 * pixels[i])
                    sum += response
                    sumOfSquares += response * response
                    count += 1
                }
            }
            let mean = sum / count
            return sumOfSquares / count - mean * mean
        }

        func luminanceStatistics() -> (mean: Double, standardDeviation: Double, p1: Double, p99: Double) {
            var histogram = [Int](repeating: 0, count: 256)
            var sum = 0.0, sumOfSquares = 0.0
            for value in pixels {
                histogram[Int((value * 255).rounded())] += 1
                sum += Double(value)
                sumOfSquares += Double(value * value)
            }
            let total = Double(pixels.count)
            let mean = sum / total
            let variance = max(0, sumOfSquares / total - mean * mean)

            func percentile(_ fraction: Double) -> Double {
                let target = fraction * total
                var seen = 0.0
                for (level, count) in histogram.enumerated() {
                    seen += Double(count)
                    if seen >= target { return Double(level) / 255 }
                }
                return 1
            }
            return (mean, variance.squareRoot(), percentile(0.01), percentile(0.99))
        }
    }
}
