import Foundation
import Testing
@testable import CleanupCore

/// The 36 constructed cases behind classifier version 2 (docs/research/agents/M05-screenshots.md, Appendix A).
/// Each case names what a wrong rule would do with it: the ids P01 to P36 match the research table.
@Suite struct ScreenshotClassifierCasesTests {
    /// A recognised line. Positions are fractions of the screenshot, origin top left.
    private func line(_ text: String, x: ClosedRange<Double> = 0.08...0.9, y: Double = 0.5) -> RecognizedLine {
        RecognizedLine(text: text, minX: x.lowerBound, maxX: x.upperBound, minY: y, maxY: y + 0.02)
    }

    private func features(
        _ lines: [RecognizedLine], barcodes: Int = 0, labels: [String: Double] = [:]
    ) -> ScreenshotFeatures {
        ScreenshotFeatures(lines: lines, barcodeCount: barcodes, labels: labels)
    }

    /// Lines stacked top to bottom from `y`, all with the same horizontal span.
    private func stack(
        _ texts: [String], x: ClosedRange<Double> = 0.08...0.9, from y: Double = 0.2, step: Double = 0.06
    ) -> [RecognizedLine] {
        texts.enumerated().map { line($1, x: x, y: y + Double($0) * step) }
    }

    private func score(_ kind: ScreenshotKind, _ screen: ScreenshotFeatures) -> Double {
        ScreenshotClassifier.scores(screen).first { $0.kind == kind }?.score ?? 0
    }

    /// The winning kind and, when given, its score.
    private func expectVerdict(
        _ id: String, _ screen: ScreenshotFeatures, _ kind: ScreenshotKind, score expected: Double? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(ScreenshotClassifier.classify(screen) == kind, "\(id) kind", sourceLocation: sourceLocation)
        guard let expected else { return }
        #expect(abs(score(kind, screen) - expected) < 0.001, "\(id) score", sourceLocation: sourceLocation)
    }

    // MARK: R1 Map needs an anchor

    @Test func p01ARecipeWithDurationsIsNotAMap() {
        let recipe = features(stack(["Pancakes", "Prep 30 min", "Cook 1 h", "Serves 4"]))
        expectVerdict("P01", recipe, .mix)
        #expect(score(.map, recipe) == 0)
    }

    @Test func p02ARunSummaryIsNotAMap() {
        let run = features(stack(["Morning run", "5.2 km", "32 min", "Great effort"]))
        expectVerdict("P02", run, .mix)
        #expect(score(.map, run) == 0)
    }

    @Test func p03AFeedWithShortTimestampsIsNotAMap() {
        let feed = features(stack(["Liam 5m", "Great game last night", "Maya 2h", "Coming to the party"]))
        expectVerdict("P03", feed, .mix)
        #expect(score(.map, feed) == 0)
    }

    @Test func p04DirectionsWithDistancesStayAMap() {
        let map = features([
            line("Directions", y: 0.8), line("12 min", y: 0.85), line("3.4 km", y: 0.88), line("Start", y: 0.92),
        ])
        expectVerdict("P04", map, .map, score: 0.8)
    }

    // MARK: R2 Chat

    @Test func p05ATrainTimetableIsNotAChat() {
        let rows = [0.2, 0.3, 0.4]
        let timetable = features(rows.flatMap { y in
            [
                line("12:41", x: 0.02...0.09, y: y),
                line("Vienna", x: 0.12...0.6, y: y),
                line("Platform 3", x: 0.75...0.95, y: y),
            ]
        })
        expectVerdict("P05", timetable, .mix)
        #expect(abs(score(.chat, timetable) - 0.3) < 0.001)
    }

    @Test func p06TwoTextColumnsSharingRowsAreNotAChat() {
        let columns = features(
            [0.2, 0.3, 0.4].flatMap { y in
                [line("Monday", x: 0.05...0.4, y: y), line("Library closed", x: 0.5...0.95, y: y)]
            } + [line("10:00", x: 0.05...0.15, y: 0.55), line("11:30", x: 0.05...0.15, y: 0.6), line("14:15", x: 0.05...0.15, y: 0.65)]
        )
        expectVerdict("P06", columns, .mix)
        #expect(abs(score(.chat, columns) - 0.3) < 0.001)
    }

    @Test func p07BubblesOnBothSidesWithTimesStayAChat() {
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
        expectVerdict("P07", chat, .chat, score: 0.85)
    }

    @Test func p29ChatAsTheFastReaderGivesItIsAChatWithoutAChatWord() {
        let chat = features([
            line("Hey are you coming tonight", x: 0.05...0.6, y: 0.20),
            line("12'.41", x: 0.05...0.15, y: 0.23),
            line("Yes save me a seat", x: 0.45...0.95, y: 0.30),
            line("12.'46", x: 0.8...0.92, y: 0.33),
            line("Great see you at eight", x: 0.05...0.6, y: 0.40),
            line("Ok see you there", x: 0.5...0.95, y: 0.50),
        ])
        expectVerdict("P29", chat, .chat, score: 0.65)
    }

    @Test func p30APriceListWithTheWordReadIsNotAChat() {
        let prices = features(
            [("Coffee", "12.50", 0.2), ("Sandwich", "8.20", 0.3), ("Cake", "3.40", 0.4)].flatMap { name, price, y in
                [line(name, x: 0.08...0.4, y: y), line(price, x: 0.7...0.9, y: y)]
            } + [line("Mark as read", x: 0.08...0.5, y: 0.6)]
        )
        expectVerdict("P30", prices, .mix)
        #expect(abs(score(.chat, prices) - 0.2) < 0.001)
    }

    @Test func p36ShortRepliesThatCarryTheTimeInlineAreStillABubble() {
        let chat = features([
            line("Are you coming tonight?", x: 0.05...0.6, y: 0.20),
            line("Ok 12:44", x: 0.75...0.95, y: 0.30),
            line("See you at eight", x: 0.05...0.6, y: 0.40),
            line("Yes 12:46", x: 0.75...0.95, y: 0.50),
            line("Thx 12:48", x: 0.75...0.95, y: 0.60),
        ])
        expectVerdict("P36", chat, .chat, score: 0.65)
    }

    // MARK: R3 Web

    @Test func p08ADomainCentredInTheBottomBarMakesAWebPage() {
        let article = features([
            line("City council approves new bike lanes", y: 0.15),
            line("We use cookies", y: 0.5),
            line("Accept all", y: 0.55),
            line("Read more", y: 0.62),
            line("bbc.com", x: 0.4...0.6, y: 0.94),
        ])
        expectVerdict("P08", article, .web, score: 0.8)
    }

    @Test func p09AnEmailAddressAtTheBottomIsNotAWebAddress() {
        let mail = features(stack(["Hi Tom", "Dinner on Friday works for me"]) + [line("anna@gmail.com", x: 0.3...0.7, y: 0.94)])
        expectVerdict("P09", mail, .mix)
        #expect(score(.web, mail) == 0)
    }

    @Test func p31AnEmailAddressInAMailHeaderIsNotAWebAddress() {
        let mail = features([line("anna@gmail.com", x: 0.1...0.5, y: 0.1)] + stack(["Hi Tom", "Dinner on Friday works for me"]))
        expectVerdict("P31", mail, .mix)
        #expect(score(.web, mail) == 0)
    }

    // MARK: R4 Receipt

    @Test func p10APolishReceiptWithTheLStrokeIsAReceipt() {
        let receipt = features(stack([
            "Paragon nr 1234", "Netto 20,24 zł", "Razem 24,90 zł", "Zapłacono 24,90 zł",
        ]))
        expectVerdict("P10", receipt, .receipt, score: 1.0)
    }

    @Test func p11AHungarianReceiptPricedInFtIsAReceipt() {
        let receipt = features(stack([
            "Nyugta", "Részösszeg 6 220 Ft", "Összesen 7 900 Ft", "Fizetve 7 900 Ft",
        ]))
        expectVerdict("P11", receipt, .receipt, score: 1.0)
    }

    @Test func p12AGermanReceiptInEurIsAReceipt() {
        let receipt = features(stack([
            "Rechnung 4711", "Zwischensumme 20,00 EUR", "MwSt 4,90 EUR", "Gesamt 24,90 EUR",
        ]))
        expectVerdict("P12", receipt, .receipt, score: 1.0)
    }

    @Test func p13ACzechReceiptInKcIsAReceipt() {
        let receipt = features(stack([
            "Účtenka", "Celkem 24,90 Kč", "DPH 4,33 Kč", "Zaplaceno 24,90 Kč",
        ]))
        expectVerdict("P13", receipt, .receipt, score: 1.0)
    }

    @Test func p14ASlovakReceiptWithWholeEurosIsAReceipt() {
        let receipt = features(stack([
            "Objednávka č. 48213", "Medzisúčet 19 €", "DPH 4 €", "Celkom 23 €",
        ]))
        expectVerdict("P14", receipt, .receipt, score: 1.0)
    }

    @Test func p26ASlovakReceiptWithTheEuroSignDroppedIsAReceipt() {
        let receipt = features(stack([
            "Objednavka c. 48213", "Medzisucet 20,00", "DPH 4,90", "Celkom 24,90",
        ]))
        expectVerdict("P26", receipt, .receipt, score: 0.8)
    }

    @Test func p27AGermanReceiptWithTheEuroSignDroppedIsAReceipt() {
        let receipt = features(stack([
            "Rechnung 4711", "Zwischensumme 20,00", "MwSt 4,90", "Gesamt 24,90",
        ]))
        expectVerdict("P27", receipt, .receipt, score: 0.8)
    }

    @Test func p15AProductPageWithTwoPricesAndOrderNowIsNotAReceipt() {
        let product = features(stack(["Wireless headphones", "99,00 €", "79,00 €", "Order now"]))
        expectVerdict("P15", product, .mix)
        #expect(abs(score(.receipt, product) - 0.3) < 0.001)
    }

    @Test func p28APriceListWithNoMoneyWordIsNotAReceipt() {
        let prices = features(
            [("Vienna", "12.50", 0.2), ("Bratislava", "8.20", 0.3)].flatMap { place, price, y in
                [line(place, x: 0.08...0.4, y: y), line(price, x: 0.7...0.9, y: y)]
            }
        )
        expectVerdict("P28", prices, .mix)
        #expect(score(.receipt, prices) == 0)
    }

    // MARK: R5 One-time codes, plain codes and tickets

    @Test func p16AGroupedCodeIsAOneTimeCode() {
        let otp = features([line("Your code is", y: 0.4), line("123 456", x: 0.3...0.7, y: 0.45)])
        expectVerdict("P16", otp, .oneTimeCode, score: 0.7)
    }

    @Test func p17AGermanCompoundWordIsAOneTimeCode() {
        let otp = features([line("Ihr Bestätigungscode lautet", y: 0.4), line("482913", x: 0.3...0.7, y: 0.45)])
        expectVerdict("P17", otp, .oneTimeCode, score: 0.7)
    }

    @Test func p18ALongReportThatMentionsCodeIsADocumentNotACode() {
        let sentence = "The quarterly report shows steady growth across every region and product line"
        var lines = (0..<11).map { line($0 == 3 ? "The source code of the billing system was rewritten in full" : sentence, y: 0.1 + Double($0) * 0.07) }
        lines.append(line("2024", x: 0.4...0.6, y: 0.88))
        let report = features(lines)
        expectVerdict("P18", report, .document, score: 0.6)
        #expect(score(.code, report) == 0)
        #expect(score(.oneTimeCode, report) == 0)
    }

    @Test func p19AQRWithTwoBookingWordsIsATicketNotACode() {
        let ticket = features([line("Ticket", y: 0.15), line("Seat 14A", y: 0.25)], barcodes: 1)
        expectVerdict("P19", ticket, .receipt, score: 0.6)
        #expect(abs(score(.code, ticket) - 0.55) < 0.001)
    }

    @Test func p20ALoyaltyCardWithABarcodeStaysACode() {
        expectVerdict("P20", features([line("Clubcard", y: 0.2)], barcodes: 1), .code, score: 0.9)
    }

    @Test func p32ACardPinStaysACode() {
        let pin = features([line("Your card PIN", y: 0.4), line("4821", x: 0.3...0.7, y: 0.45)])
        expectVerdict("P32", pin, .code, score: 0.7)
        #expect(score(.oneTimeCode, pin) == 0)
    }

    @Test func p33AWifiPasswordStaysACode() {
        let wifi = features([line("Wi-Fi heslo", y: 0.4), line("12345678", x: 0.3...0.7, y: 0.45)])
        expectVerdict("P33", wifi, .code, score: 0.7)
        #expect(score(.oneTimeCode, wifi) == 0)
    }

    @Test func p34ARecoveryCodeListStaysACode() {
        let recovery = features(stack(["Recovery code list", "48213907", "55120384", "90317746", "27704519"]))
        expectVerdict("P34", recovery, .code, score: 0.7)
        #expect(score(.oneTimeCode, recovery) == 0)
    }

    @Test func p35AParcelPickupCodeStaysACode() {
        let pickup = features([line("Kod na vyzdvihnutie", y: 0.4), line("482913", x: 0.3...0.7, y: 0.45)])
        expectVerdict("P35", pickup, .code, score: 0.7)
        #expect(score(.oneTimeCode, pickup) == 0)
    }

    // MARK: R6 Interface labels

    @Test func p21ACalendarScreenIsNotAPicture() {
        let calendar = features([line("September 2026", y: 0.15), line("Today", y: 0.3)], labels: ["calendar": 0.8])
        expectVerdict("P21", calendar, .mix)
        #expect(score(.photo, calendar) == 0)
    }

    @Test func p22AThankYouScreenLabelledReceiptIsNotAPicture() {
        let thanks = features([line("Thank you", y: 0.4), line("See you soon", y: 0.46)], labels: ["receipt": 0.8])
        expectVerdict("P22", thanks, .mix)
        #expect(score(.photo, thanks) == 0)
    }

    @Test func p23ADogPhotoWithTheWordLolStaysAPicture() {
        let dog = features([line("lol", y: 0.9)], labels: ["dog": 0.8, "screenshot": 0.4])
        expectVerdict("P23", dog, .photo, score: 0.6)
    }

    // MARK: R7 Vocabulary

    @Test func p24AFeedPostWithLikedByAndViewAllIsSocial() {
        let post = features(stack(["Liked by anna_k and others", "View all 35 comments", "Add a comment"]))
        expectVerdict("P24", post, .social, score: 0.5)
    }

    @Test func p25AMailWithOnlyReplyAndShareIsNotSocial() {
        let mail = features(stack(["Reply", "Share"]))
        expectVerdict("P25", mail, .mix)
        #expect(abs(score(.social, mail) - 0.4) < 0.001)
    }

    // MARK: R8 Text helpers

    @Test func foldRemovesThePolishLStroke() {
        #expect(ScreenshotClassifier.fold("Zapłacono") == "zaplacono")
    }

    @Test func aPhraseMustMatchWholeWords() {
        #expect(ScreenshotClassifier.wordHits(["sign in"], in: "we design internal tools") == 0)
        #expect(ScreenshotClassifier.wordHits(["sign in"], in: "please sign in now") == 1)
    }

    // MARK: R9 Version and the new kind in the app's ordering

    @Test func theClassifierVersionIsTwo() {
        #expect(ScreenshotClassifier.version == 2)
    }

    @Test func oneTimeCodeRoundTripsThroughItsRawValue() {
        #expect(ScreenshotKind.oneTimeCode.rawValue == "oneTimeCode")
        #expect(ScreenshotKind(rawValue: "oneTimeCode") == .oneTimeCode)
    }

    @Test func oneTimeCodesSortBySizeWithMixLastAndTiesByRawValue() {
        func shot(_ id: String, _ kind: ScreenshotKind, bytes: Int64) -> CleanupItem {
            CleanupItem(id: id, byteSize: bytes, creationDate: .distantPast, screenshotKind: kind)
        }
        var sectioned = ScanResult(screenshots: [
            shot("m", .mix, bytes: 9_000), shot("c", .code, bytes: 1_000),
            shot("o", .oneTimeCode, bytes: 1_000), shot("r", .receipt, bytes: 5_000),
        ])
        sectioned.arrangeScreenshots()
        #expect(sectioned.screenshotSections.map(\.kind) == [.receipt, .code, .oneTimeCode, .mix])
    }
}
