import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import Testing
@testable import CleanupCore

/// Runs Vision on drawn screens, so it needs a real Mac (CI skips it, like the fingerprint tests).
@Suite struct ScreenshotAnalyzerTests {
    private static let width = 1179, height = 2556

    /// A phone-sized white screen with black text. `y` is a fraction of the height from the top.
    private func screen(_ lines: [(text: String, x: Double, y: Double)], qr: String? = nil) -> CGImage {
        let context = CGContext(
            data: nil, width: Self.width, height: Self.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 60, nil)
        for line in lines {
            let attributed = NSAttributedString(string: line.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ])
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.textPosition = CGPoint(x: line.x * Double(Self.width), y: (1 - line.y) * Double(Self.height))
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        if let qr {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(qr.utf8)
            let code = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 24, y: 24))
            let image = CIContext().createCGImage(code, from: code.extent)!
            context.draw(image, in: CGRect(x: 200, y: 900, width: 780, height: 780))
        }
        return context.makeImage()!
    }

    @Test func textPositionsAreMeasuredFromTheTop() throws {
        let features = try ScreenshotAnalyzer.features(of: screen([
            (text: "Quarterly revenue report", x: 0.1, y: 0.2),
            (text: "Confidential draft copy", x: 0.1, y: 0.8),
        ]))
        let top = try #require(features.lines.first { $0.text.contains("revenue") })
        let bottom = try #require(features.lines.first { $0.text.contains("draft") })
        #expect(top.maxY < 0.3 && top.minY < top.maxY)
        #expect(bottom.minY > 0.7)
        #expect(top.minX < 0.2 && top.maxX > 0.4)
    }

    @Test func amountsAndOrderWordsAreReadAsAReceipt() throws {
        let kind = try ScreenshotAnalyzer.kind(of: screen([
            (text: "Order confirmation", x: 0.1, y: 0.2),
            (text: "Subtotal $20.00", x: 0.1, y: 0.3),
            (text: "VAT $4.90", x: 0.1, y: 0.35),
            (text: "Total $24.90", x: 0.1, y: 0.4),
        ]))
        #expect(kind == .receipt)
    }

    @Test func aQRCodeIsFoundAndReadAsACode() throws {
        let image = screen([(text: "Scan at the door", x: 0.1, y: 0.15)], qr: "https://example.com/ticket/42")
        #expect(try ScreenshotAnalyzer.features(of: image).barcodeCount >= 1)
        #expect(try ScreenshotAnalyzer.kind(of: image) == .code)
    }

    @Test func aBlankScreenHasNoTextAndStaysInMix() throws {
        let image = screen([])
        #expect(try ScreenshotAnalyzer.features(of: image).lines.isEmpty)
        #expect(try ScreenshotAnalyzer.kind(of: image) == .mix)
    }
}
