import Accelerate
import CoreGraphics
import Foundation
import Vision

/// Compact image embedding. Half precision keeps the on-device cache small.
public struct Fingerprint: Sendable, Equatable {
    public let values: [Float16]

    public init(_ floats: [Float]) {
        values = floats.map { Float16($0) }
    }

    public init?(data: Data) {
        guard !data.isEmpty, data.count % MemoryLayout<Float16>.size == 0 else { return nil }
        var values = [Float16](repeating: 0, count: data.count / MemoryLayout<Float16>.size)
        _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        self.values = values
    }

    public var data: Data {
        values.withUnsafeBytes { Data($0) }
    }

    var floats: [Float] {
        values.map { Float($0) }
    }

    /// Euclidean distance. Only meaningful between fingerprints from the same fingerprinter.
    public func distance(to other: Fingerprint) -> Float {
        distance(toFloats: other.floats)
    }

    func distance(toFloats other: [Float]) -> Float {
        guard values.count == other.count else { return .infinity }
        return vDSP.distanceSquared(floats, other).squareRoot()
    }
}

public protocol Fingerprinter: Sendable {
    /// Stored next to cached fingerprints. A different identifier invalidates the cache.
    var identifier: String { get }
    func fingerprint(of image: CGImage) throws -> Fingerprint
}

public enum FingerprintError: Error {
    case unexpectedFeaturePrint
    case unreadableImage
}

/// Vision feature print, revision pinned so cached values stay comparable across OS updates.
public struct VisionFingerprinter: Fingerprinter {
    public let identifier = "vision-feature-print-r2"

    public init() {}

    public func fingerprint(of image: CGImage) throws -> Fingerprint {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let observation = request.results?.first,
              observation.elementType == .float,
              observation.elementCount > 0
        else { throw FingerprintError.unexpectedFeaturePrint }
        let floats = observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return Fingerprint(floats)
    }
}

/// 16x16 colour thumbnail, centred and normalised. Weaker than Vision (no tolerance for reframing),
/// but it runs in the Simulator, where Vision returns near-identical vectors for every photo.
public struct TinyImageFingerprinter: Fingerprinter {
    public let identifier = "tiny-image-16"

    public init() {}

    public func fingerprint(of image: CGImage) throws -> Fingerprint {
        let side = 16
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { throw FingerprintError.unreadableImage }
        var floats: [Float] = []
        floats.reserveCapacity(side * side * 3)
        for pixel in 0..<(side * side) {
            for channel in 0..<3 { floats.append(Float(bytes[pixel * 4 + channel]) / 255) }
        }
        let mean = vDSP.mean(floats)
        floats = floats.map { $0 - mean }
        let norm = max(vDSP.sumOfSquares(floats).squareRoot(), 1e-6)
        return Fingerprint(floats.map { $0 / norm })
    }
}
