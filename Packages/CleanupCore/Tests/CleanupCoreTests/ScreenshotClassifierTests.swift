import Testing
@testable import CleanupCore

@Suite struct ScreenshotClassifierTests {
    /// A recognised line. Positions are fractions of the screenshot, origin top left.
    private func line(_ text: String, x: ClosedRange<Double> = 0.08...0.9, y: Double = 0.5) -> RecognizedLine {
        RecognizedLine(text: text, minX: x.lowerBound, maxX: x.upperBound, minY: y, maxY: y + 0.02)
    }

    private func features(
        _ lines: [RecognizedLine], barcodes: Int = 0, labels: [String: Double] = [:]
    ) -> ScreenshotFeatures {
        ScreenshotFeatures(lines: lines, barcodeCount: barcodes, labels: labels)
    }

    @Test func aConversationWithTimesAndBubblesOnBothSidesIsAChat() {
        let chat = features([
            line("Hey, are you coming tonight?", x: 0.05...0.6, y: 0.20),
            line("12:41", x: 0.05...0.15, y: 0.23),
            line("Yes! Save me a seat", x: 0.45...0.95, y: 0.30),
            line("12:42", x: 0.8...0.92, y: 0.33),
            line("Great, see you at eight", x: 0.05...0.6, y: 0.40),
            line("12:43", x: 0.05...0.15, y: 0.43),
            line("Ok", x: 0.8...0.95, y: 0.50),
            line("Delivered", x: 0.8...0.95, y: 0.53),
        ])
        #expect(ScreenshotClassifier.classify(chat) == .chat)
    }

    @Test func amountsAndOrderWordsMakeAReceipt() {
        let receipt = features([
            line("Order confirmation", y: 0.15),
            line("Subtotal €20.00", y: 0.25),
            line("VAT €4.90", y: 0.30),
            line("Total €24.90", y: 0.35),
        ])
        #expect(ScreenshotClassifier.classify(receipt) == .receipt)
    }

    @Test func slovakReceiptWordsAreMatchedWithoutDiacritics() {
        let receipt = features([
            line("Objednávka č. 48213", y: 0.15),
            line("Medzisúčet 20,00 €", y: 0.25),
            line("DPH 4,90 €", y: 0.30),
            line("Celkom 24,90 €", y: 0.35),
        ])
        #expect(ScreenshotClassifier.classify(receipt) == .receipt)
    }

    @Test func aBarcodeWithLittleElseIsACode() {
        #expect(ScreenshotClassifier.classify(features([line("Scan me", y: 0.7)], barcodes: 1)) == .code)
    }

    @Test func aBarcodeWithBookingWordsIsATicketNotJustACode() {
        let ticket = features([
            line("Boarding pass", y: 0.15),
            line("Flight OK123", y: 0.25),
            line("Gate B12", y: 0.30),
            line("Seat 14A", y: 0.35),
        ], barcodes: 1)
        #expect(ScreenshotClassifier.classify(ticket) == .receipt)
    }

    @Test func aVerificationCodeMessageIsACode() {
        let otp = features([
            line("Your verification code is", y: 0.4),
            line("482913", x: 0.3...0.7, y: 0.45),
        ])
        #expect(ScreenshotClassifier.classify(otp) == .code)
    }

    @Test func distancesAndDirectionsMakeAMap() {
        let map = features([
            line("Directions", y: 0.8),
            line("12 min", y: 0.85),
            line("3.4 km", y: 0.88),
            line("Start", y: 0.92),
        ])
        #expect(ScreenshotClassifier.classify(map) == .map)
    }

    @Test func theMapLabelAloneIsEnoughForAMapWithFewWords() {
        #expect(ScreenshotClassifier.classify(features([line("Bratislava", y: 0.2)], labels: ["map": 0.7])) == .map)
    }

    @Test func aDomainNameAtTheTopWithCookieWordsIsAWebPage() {
        let web = features([
            line("bbc.com/news", x: 0.2...0.8, y: 0.08),
            line("We use cookies", y: 0.5),
            line("Accept all", y: 0.55),
            line("Read more", y: 0.62),
        ])
        #expect(ScreenshotClassifier.classify(web) == .web)
    }

    @Test func handlesLikesAndRepliesMakeASocialPost() {
        let post = features([
            line("@anna_k", y: 0.15),
            line("12.4K likes", y: 0.7),
            line("Reply", y: 0.75),
            line("Share", y: 0.8),
        ])
        #expect(ScreenshotClassifier.classify(post) == .social)
    }

    @Test func aDensePageOfLongLinesIsADocument() {
        let paragraph = "The quarterly report shows steady growth across every region and product line"
        let page = features((0..<28).map { line(paragraph, y: 0.08 + Double($0) * 0.031) })
        #expect(ScreenshotClassifier.classify(page) == .document)
    }

    @Test func aScreenWithAlmostNoTextAndAPhotoLabelIsAPhoto() {
        let photo = features([line("lol", y: 0.9)], labels: ["dog": 0.8, "screenshot": 0.4])
        #expect(ScreenshotClassifier.classify(photo) == .photo)
    }

    @Test func anOrdinaryAppScreenStaysInMix() {
        let settings = features([
            line("Settings", y: 0.12), line("Wi-Fi", y: 0.25), line("Bluetooth", y: 0.32),
            line("Battery", y: 0.39), line("General", y: 0.46),
        ], labels: ["document": 0.9, "screenshot": 0.9])
        #expect(ScreenshotClassifier.classify(settings) == .mix)
    }

    @Test func noTextAtAllStaysInMix() {
        #expect(ScreenshotClassifier.classify(features([])) == .mix)
    }

    @Test func theClockInTheStatusBarDoesNotMakeAChat() {
        let screen = features([
            line("9:41", x: 0.1...0.2, y: 0.02),
            line("Settings", y: 0.12),
            line("General", y: 0.3),
        ])
        #expect(ScreenshotClassifier.classify(screen) == .mix)
    }
}
