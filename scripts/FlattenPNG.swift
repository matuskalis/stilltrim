// Redraws a PNG into an opaque sRGB bitmap of 1024 x 1024 pixels, so it carries no alpha channel.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let input = CommandLine.arguments[1], output = CommandLine.arguments[2]
let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let context = CGContext(
    data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination), "could not write \(output)")
