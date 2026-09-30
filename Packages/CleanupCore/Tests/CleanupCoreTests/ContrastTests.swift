import Testing
@testable import CleanupCore

@Suite struct ContrastTests {
    typealias RGB = (red: Double, green: Double, blue: Double)

    private func grey(_ v: Double) -> RGB { (v, v, v) }
    private func hex(_ r: Int, _ g: Int, _ b: Int) -> RGB { (Double(r) / 255, Double(g) / 255, Double(b) / 255) }
    private func over(_ scrim: Double, _ photo: RGB) -> RGB {
        (photo.red * (1 - scrim), photo.green * (1 - scrim), photo.blue * (1 - scrim))
    }

    private let white = (red: 1.0, green: 1.0, blue: 1.0)
    private let black = (red: 0.0, green: 0.0, blue: 0.0)
    private let lightAccent = (red: 0xD1 / 255.0, green: 0x2E / 255.0, blue: 0x1F / 255.0)
    private let darkAccent = (red: 0xFF / 255.0, green: 0x5B / 255.0, blue: 0x47 / 255.0)

    private var backdrops: [(String, RGB)] {
        [
            ("black", black), ("white", white), ("mid grey", grey(0.5)), ("light sky", hex(135, 206, 235)),
            ("red-orange", hex(255, 69, 0)), ("green", hex(0, 160, 60)), ("night", hex(10, 12, 30)),
            ("accent light", lightAccent), ("accent dark", darkAccent),
        ]
    }

    @Test func knownRatios() {
        #expect(abs(Contrast.ratio(black, white) - 21) < 0.001)
        #expect(abs(Contrast.ratio(white, white) - 1) < 0.001)
    }

    /// The white ring sits between a dark disc (inside) and a dark keyline (outside), so on any photo at
    /// least one side is 3:1 or better against it.
    @Test func whiteRingSeparatesFromAnyPhoto() {
        for (name, photo) in backdrops {
            let inside = Contrast.ratio(white, over(SelectionMarkSpec.discScrimOpacity, photo))
            let outside = Contrast.ratio(white, over(SelectionMarkSpec.keylineOpacity, photo))
            #expect(max(inside, outside) >= 3, "ring on \(name)")
        }
    }

    @Test func pillTextReadsOnScrimOverAnyPhoto() {
        for (name, photo) in backdrops {
            #expect(Contrast.ratio(white, over(SelectionMarkSpec.pillScrimOpacity, photo)) >= 4.5, "pill on \(name)")
        }
    }

    @Test func checkGlyphReadsOnTheAccent() {
        #expect(Contrast.ratio(white, lightAccent) >= 4.5)
        #expect(Contrast.ratio(black, darkAccent) >= 4.5)
    }
}
