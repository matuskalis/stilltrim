import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Synthetic {
    private static let rgb = CGColorSpaceCreateDeviceRGB()

    private static func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    private static func randomColor(_ rng: inout SeededGenerator) -> CGColor {
        CGColor(
            red: .random(in: 0...1, using: &rng),
            green: .random(in: 0...1, using: &rng),
            blue: .random(in: 0...1, using: &rng),
            alpha: 1
        )
    }

    /// Gradient background with many random shapes at several sizes, so edges exist at every scale.
    static func scene(seed: UInt64, width: Int = 1600, height: Int = 1066) -> CGImage {
        var rng = SeededGenerator(seed: seed)
        let context = makeContext(width: width, height: height)
        let gradient = CGGradient(
            colorsSpace: rgb, colors: [randomColor(&rng), randomColor(&rng)] as CFArray, locations: [0, 1]
        )!
        context.drawLinearGradient(
            gradient, start: .zero, end: CGPoint(x: width, y: height), options: []
        )
        let shortSide = CGFloat(min(width, height))
        for _ in 0..<400 {
            let size = CGFloat.random(in: 6...(shortSide / 3), using: &rng)
            let rect = CGRect(
                x: .random(in: 0...CGFloat(width), using: &rng),
                y: .random(in: 0...CGFloat(height), using: &rng),
                width: size,
                height: size * .random(in: 0.4...1.6, using: &rng)
            )
            context.setFillColor(randomColor(&rng))
            if Bool.random(using: &rng) { context.fillEllipse(in: rect) } else { context.fill(rect) }
        }
        return context.makeImage()!
    }

    /// One flat colour with optional low-amplitude noise.
    static func flat(gray: CGFloat, noise: CGFloat = 0, seed: UInt64 = 1, width: Int = 800, height: Int = 600) -> CGImage {
        var rng = SeededGenerator(seed: seed)
        let context = makeContext(width: width, height: height)
        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if noise > 0 {
            for _ in 0..<4000 {
                let value = min(1, max(0, gray + .random(in: -noise...noise, using: &rng)))
                context.setFillColor(CGColor(red: value, green: value, blue: value, alpha: 1))
                context.fill(CGRect(
                    x: Int.random(in: 0..<width, using: &rng), y: Int.random(in: 0..<height, using: &rng),
                    width: 3, height: 3
                ))
            }
        }
        return context.makeImage()!
    }

    /// Dark night frame with a few bright lights.
    static func nightWithLights(width: Int = 1200, height: Int = 800) -> CGImage {
        var rng = SeededGenerator(seed: 7)
        let context = makeContext(width: width, height: height)
        context.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for _ in 0..<60 {
            let size = CGFloat.random(in: 14...40, using: &rng)
            context.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.6, alpha: 1))
            context.fillEllipse(in: CGRect(
                x: .random(in: 0...CGFloat(width), using: &rng),
                y: .random(in: 0...CGFloat(height), using: &rng),
                width: size, height: size
            ))
        }
        return context.makeImage()!
    }

    static func blurred(_ image: CGImage, sigma: Double) -> CGImage {
        let input = CIImage(cgImage: image)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.clampedToExtent()
        filter.radius = Float(sigma)
        return CIContext().createCGImage(filter.outputImage!.cropped(to: input.extent), from: input.extent)!
    }

    static func exposure(_ image: CGImage, ev: Float) -> CGImage {
        let input = CIImage(cgImage: image)
        let filter = CIFilter.exposureAdjust()
        filter.inputImage = input
        filter.ev = ev
        return CIContext().createCGImage(filter.outputImage!, from: input.extent)!
    }

    static func resized(_ image: CGImage, longSide: Int) -> CGImage {
        let scale = Double(longSide) / Double(max(image.width, image.height))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let context = makeContext(width: width, height: height)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// The bytes a library would store for this image saved as a JPEG.
    static func jpegData(_ image: CGImage, quality: Double) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func jpeg(_ image: CGImage, quality: Double) -> CGImage {
        CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(jpegData(image, quality: quality) as CFData, nil)!, 0, nil)!
    }

    static func cropped(_ image: CGImage, fraction: Double, dx: Double = 0, dy: Double = 0) -> CGImage {
        let width = Double(image.width), height = Double(image.height)
        let cropWidth = width * fraction, cropHeight = height * fraction
        let x = (width - cropWidth) / 2 * (1 + dx), y = (height - cropHeight) / 2 * (1 + dy)
        return image.cropping(to: CGRect(x: x, y: y, width: cropWidth, height: cropHeight))!
    }
}
