// Generates test media into the folder given as argument 2, from the photos in argument 1.
// Run through scripts/seed-simulator.sh.
import AVFoundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

let fixtures = CommandLine.arguments[1]
let out = CommandLine.arguments[2]
let ciContext = CIContext()
let rgb = CGColorSpaceCreateDeviceRGB()

func load(_ name: String) -> CGImage {
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(fixtures)/\(name).jpg") as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(source, 0, nil)!
}

func exifDate(_ offsetSeconds: Int) -> String {
    let base = Date(timeIntervalSince1970: 1_780_000_000 + Double(offsetSeconds))
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: base)
}

func write(_ image: CGImage, as name: String, type: UTType = .jpeg, at offset: Int, comment: String? = nil, quality: Double = 0.9) {
    let url = URL(fileURLWithPath: "\(out)/\(name).\(type == .png ? "png" : "jpg")")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    var exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: exifDate(offset)]
    if let comment { exif[kCGImagePropertyExifUserComment] = comment }
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyExifDictionary: exif,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: exifDate(offset)],
        kCGImageDestinationLossyCompressionQuality: quality,
    ] as CFDictionary)
    precondition(CGImageDestinationFinalize(destination), "could not write \(name)")
}

func cropped(_ image: CGImage, fraction: Double, dx: Double, dy: Double) -> CGImage {
    let w = Double(image.width), h = Double(image.height)
    let cw = w * fraction, ch = h * fraction
    return image.cropping(to: CGRect(x: (w - cw) / 2 * (1 + dx), y: (h - ch) / 2 * (1 + dy), width: cw, height: ch))!
}

func blurred(_ image: CGImage, sigma: Double) -> CGImage {
    let input = CIImage(cgImage: image)
    let filter = CIFilter.gaussianBlur()
    filter.inputImage = input.clampedToExtent()
    filter.radius = Float(sigma)
    return ciContext.createCGImage(filter.outputImage!.cropped(to: input.extent), from: input.extent)!
}

func solid(red: CGFloat, green: CGFloat, blue: CGFloat, noise: CGFloat) -> CGImage {
    let context = CGContext(data: nil, width: 1600, height: 1200, bitsPerComponent: 8, bytesPerRow: 0, space: rgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
    for _ in 0..<3000 {
        let jitter = CGFloat.random(in: -noise...noise)
        context.setFillColor(CGColor(red: min(1, max(0, red + jitter)), green: min(1, max(0, green + jitter)), blue: min(1, max(0, blue + jitter)), alpha: 1))
        context.fill(CGRect(x: Int.random(in: 0..<1600), y: Int.random(in: 0..<1200), width: 3, height: 3))
    }
    return context.makeImage()!
}

func fakeScreenshot(seed: Int) -> CGImage {
    let width = 1206, height = 2622
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: rgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.2, green: 0.45 + CGFloat(seed) * 0.15, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: height - 260, width: width, height: 260))
    for row in 0..<14 {
        let y = height - 400 - row * 170
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 40, y: y, width: width - 80, height: 140))
        context.setFillColor(CGColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1))
        context.fill(CGRect(x: 90, y: y + 80, width: 420 + (row * 53 + seed * 97) % 380, height: 22))
        context.setFillColor(CGColor(red: 0.6, green: 0.6, blue: 0.64, alpha: 1))
        context.fill(CGRect(x: 90, y: y + 34, width: 260 + (row * 71 + seed * 41) % 300, height: 16))
    }
    return context.makeImage()!
}

func makeVideo(name: String, seconds: Int, bitrate: Int) {
    let url = URL(fileURLWithPath: "\(out)/\(name).mov")
    try? FileManager.default.removeItem(at: url)
    let width = 1920, height = 1080
    let writer = try! AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<(seconds * 30) {
        while !input.isReadyForMoreMediaData { usleep(2000) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        CVPixelBufferLockBaseAddress(buffer!, [])
        arc4random_buf(CVPixelBufferGetBaseAddress(buffer!), CVPixelBufferGetDataSize(buffer!))
        CVPixelBufferUnlockBaseAddress(buffer!, [])
        adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
}

try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

// Five scenes, each with an original and two near-duplicates.
for (index, name) in ["p10", "p11", "p13", "p14", "p15"].enumerated() {
    let base = load(name)
    let start = index * 3_600
    write(base, as: "scene\(index)-a", at: start)
    write(base, as: "scene\(index)-b", at: start + 20, quality: 0.4)
    write(cropped(base, fraction: 0.9, dx: 1, dy: 1), as: "scene\(index)-c", at: start + 40)
}
// Unrelated single shots.
for (index, name) in ["p16", "p17", "p18", "p19"].enumerated() {
    write(load(name), as: "single\(index)", at: 30_000 + index * 3_600)
}
// Blurry shots.
for (index, (name, sigma)) in [("p20", 3.0), ("p21", 6.0), ("p22", 4.0)].enumerated() {
    write(blurred(load(name), sigma: sigma), as: "blurry\(index)", at: 50_000 + index * 3_600)
}
// Accidental frames: lens covered, pocket, white-out.
write(solid(red: 0.01, green: 0.01, blue: 0.012, noise: 0.004), as: "accidental-black", at: 70_000)
write(solid(red: 0.99, green: 0.99, blue: 0.99, noise: 0.004), as: "accidental-white", at: 73_600)
write(solid(red: 0.55, green: 0.28, blue: 0.26, noise: 0.004), as: "accidental-finger", at: 77_200)
// Screenshots, tagged the way iOS tags its own.
for index in 0..<3 {
    write(fakeScreenshot(seed: index), as: "screenshot\(index)", type: .png, at: 90_000 + index * 3_600, comment: "Screenshot")
}
makeVideo(name: "big-video", seconds: 6, bitrate: 100_000_000)
print("wrote \(try! FileManager.default.contentsOfDirectory(atPath: out).count) files to \(out)")
