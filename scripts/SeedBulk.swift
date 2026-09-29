// Generates N small JPEGs into folder argument 2 from the photos in argument 1, for scale tests.
// About one in six is a near-duplicate of the photo before it. Run through scripts/seed-bulk.sh.
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

let fixtures = CommandLine.arguments[1]
let out = CommandLine.arguments[2]
let count = Int(CommandLine.arguments[3])!
let ciContext = CIContext()

let names = try! FileManager.default.contentsOfDirectory(atPath: fixtures).filter { $0.hasSuffix(".jpg") }.sorted()
let sources: [CGImage] = names.map {
    CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(fixtures)/\($0)") as CFURL, nil)!, 0, nil)!
}

struct Generator: RandomNumberGenerator {
    var state: UInt64 = 42
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
var rng = Generator()

func dateString(_ seconds: Int) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: Date(timeIntervalSince1970: 1_770_000_000 + Double(seconds)))
}

func variant(of source: CGImage, crop: Double, ev: Float) -> CGImage {
    let w = Double(source.width), h = Double(source.height)
    let cw = w * crop, ch = h * crop
    let x = Double.random(in: 0...(w - cw), using: &rng), y = Double.random(in: 0...(h - ch), using: &rng)
    let cropped = CIImage(cgImage: source.cropping(to: CGRect(x: x, y: y, width: cw, height: ch))!)
    let exposed = cropped.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: ev])
    let scale = 640 / cw
    let scaled = exposed.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    return ciContext.createCGImage(scaled, from: scaled.extent.integral)!
}

func write(_ image: CGImage, index: Int, seconds: Int) {
    let url = URL(fileURLWithPath: "\(out)/bulk\(String(format: "%05d", index)).jpg")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: dateString(seconds)],
        kCGImageDestinationLossyCompressionQuality: 0.8,
    ] as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
}

try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
var clock = 0
var previous: (source: Int, crop: Double)?
for index in 0..<count {
    if let previous, Int.random(in: 0..<6, using: &rng) == 0 {
        clock += Int.random(in: 2...40, using: &rng)
        write(variant(of: sources[previous.source], crop: previous.crop, ev: Float.random(in: -0.2...0.2, using: &rng)), index: index, seconds: clock)
    } else {
        let source = Int.random(in: 0..<sources.count, using: &rng)
        let crop = Double.random(in: 0.35...1, using: &rng)
        clock += Int.random(in: 600...30_000, using: &rng)
        write(variant(of: sources[source], crop: crop, ev: Float.random(in: -0.5...0.5, using: &rng)), index: index, seconds: clock)
        previous = (source, crop)
    }
}
print("wrote \(count) files to \(out)")
