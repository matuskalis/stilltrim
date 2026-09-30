import Foundation

public enum ScreenshotKind: String, CaseIterable, Sendable, Codable {
    case chat, receipt, code, oneTimeCode, map, web, social, document, photo, recording, mix
}

/// One line of recognised text. Positions are fractions of the screenshot, origin top left.
public struct RecognizedLine: Sendable, Equatable {
    public var text: String
    public var minX: Double
    public var maxX: Double
    public var minY: Double
    public var maxY: Double

    public init(text: String, minX: Double, maxX: Double, minY: Double, maxY: Double) {
        self.text = text
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }
}

/// What the classifier needs from a screenshot, so it can be tested without Vision.
public struct ScreenshotFeatures: Sendable, Equatable {
    public var lines: [RecognizedLine]
    public var barcodeCount: Int
    /// Vision classification label to confidence.
    public var labels: [String: Double]

    public init(lines: [RecognizedLine], barcodeCount: Int, labels: [String: Double]) {
        self.lines = lines
        self.barcodeCount = barcodeCount
        self.labels = labels
    }
}

/// Sorts a screenshot into one kind from what is on it. A rule-based first version: each kind earns a
/// score from a few signals, the best score wins, and anything below the bar is "mix". A wrong guess
/// only files a screenshot under another heading, nothing is ever pre-selected by kind.
public enum ScreenshotClassifier {
    /// Stored next to each cached kind. Raise it when the rules change, so screenshots are read again.
    public static let version = 2

    private static let minimumScore = 0.5
    /// Clock, signal and battery live above this line, the home indicator below the other.
    private static let statusBarBottom = 0.06
    private static let homeIndicatorTop = 0.97

    private static let moneyWords = [
        "total", "subtotal", "tax", "vat", "order", "invoice", "receipt", "payment", "paid", "amount",
        "objednavka", "faktura", "uctenka", "platba", "celkom", "suma", "dph", "medzisucet", "objednavku",
        "celkem", "mezisoucet", "zaplaceno",
        "bestellung", "rechnung", "gesamt", "gesamtsumme", "zwischensumme", "mwst", "quittung", "bezahlt", "betrag",
        "rendeles", "szamla", "osszesen", "reszosszeg", "afa", "fizetve", "nyugta",
        "zamowienie", "paragon", "razem", "zaplacono", "platnosc", "brutto", "netto",
    ]
    private static let bookingWords = [
        "ticket", "boarding", "gate", "seat", "flight", "booking", "confirmation", "reservation",
        "letenka", "listok", "rezervacia", "potvrdenie", "jizdenka", "vstupenka", "rezervace", "potvrzeni",
        "fahrkarte", "flug", "buchung", "reservierung", "sitzplatz", "jegy", "foglalas", "repulojegy",
        "bilet", "rezerwacja", "potwierdzenie",
    ]
    private static let chatWords = [
        "delivered", "read", "seen", "typing", "imessage", "whatsapp", "type a message", "message",
        "sprava", "napiste", "dorucene", "precitane",
        "doruceno", "precteno", "zugestellt", "gelesen", "nachricht", "dostarczono", "przeczytano", "kezbesitve",
    ]
    private static let mapWords = [
        "directions", "route", "navigate", "eta", "arrive", "traffic", "start", "trasa", "navigovat",
        "navigace", "navigation", "nawiguj", "utvonal",
    ]
    private static let webWords = [
        "cookie", "cookies", "accept", "subscribe", "sign in", "read more", "advertisement",
        "privacy policy", "prijat", "suhlasim", "souhlasim", "akzeptieren",
    ]
    private static let socialWords = [
        "likes", "comments", "share", "followers", "following", "reply", "retweet", "repost", "reels",
        "story", "views", "follow", "sledovatelov", "odpovedat", "zdielat",
        "liked by", "view all", "add a comment", "reposts", "upvotes", "bookmarks", "subscribers",
        "paci sa mi to", "komentarov",
    ]
    private static let codeWords = [
        "code", "verification", "verifizierung", "otp", "kod", "overenie", "overovaci",
        "weryfikacyjny", "ellenorzo", "einmalpasswort",
    ]
    /// A secret or a code that stays valid is a plain code, never a one-time code.
    private static let secretWords = ["password", "passwort", "heslo", "haslo", "jelszo", "pin"]
    private static let keepWords = [
        "wifi", "wi fi", "backup", "recovery", "restore", "zaloha", "zalozny", "obnovenie", "obnovovaci",
        "pickup", "locker", "vyzdvihnutie", "vydajne", "zasielkovna", "packeta",
    ]
    private static let notCodeCompounds: Set<String> = ["barcode", "qrcode", "postcode", "zipcode"]
    private static let interfaceLabels: Set<String> = [
        "screenshot", "document", "map", "chart", "diagram", "flipchart", "book", "checkbook", "computer",
        "computer_monitor", "credit_card", "gift_card", "whiteboard", "newspaper", "magazine", "sign",
        "receipt", "ticket", "printed_page", "banner", "calendar", "clock", "table", "television", "phone",
        "consumer_electronics", "computer_keyboard", "envelope", "passport",
    ]

    private static let rowTolerance = 0.012
    /// A clock time. The fast reader often turns the colon into an apostrophe and a dot: "12'.41".
    private static let timePattern = #"(?<![\d.,])(?:[01]?\d|2[0-3])\s?(?:[:'’]\.?|\.['’])\s?[0-5]\d(?!\d)"#
    private static let loneNumberPattern = #"^\D*(?:\d{4,8}|\d{3}[ -]\d{3}|\d{4}[ -]\d{4})\D*$"#
    private static let amountPattern = [
        #"[€$£]\s?\d{1,3}(?:[ .,\u00A0]\d{3})*(?:[.,]\d{2})?"#,
        #"\d{1,3}(?:[ .,\u00A0]\d{3})*[.,]\d{2}\s?(?:€|\$|£|eur|usd|czk|kc|pln|zl|huf|ft|chf)"#,
        #"\d{1,3}(?:[ \u00A0]\d{3})*\s?(?:€|\$|£|kc|zl|ft)(?![a-z])"#,
        #"\b(?:eur|usd|gbp|czk|pln|huf|chf)\s?\d{1,3}(?:[ .,\u00A0]\d{3})*(?:[.,]\d{2})?"#,
    ].joined(separator: "|")
    /// The fast reader drops the euro sign, so "20,00" alone still counts as an amount next to a money word.
    private static let bareDecimalPattern = #"(?<![\d.,])\d{1,3}(?:[ .,\u00A0]\d{3})*[.,]\d{2}(?!\d)"#

    public static func classify(_ features: ScreenshotFeatures) -> ScreenshotKind {
        var best: (kind: ScreenshotKind, score: Double) = (.mix, 0)
        for (kind, score) in scores(features) where score > best.score { best = (kind, score) }
        return best.score >= minimumScore ? best.kind : .mix
    }

    /// Every kind's score in a fixed order, so a tie is always settled the same way.
    static func scores(_ features: ScreenshotFeatures) -> [(kind: ScreenshotKind, score: Double)] {
        let body = features.lines.filter { $0.minY >= statusBarBottom && $0.maxY <= homeIndicatorTop }
        let texts = body.map { fold($0.text) }
        let text = texts.joined(separator: "\n")
        let rowTexts = rows(of: body)
        let bookingHits = wordHits(bookingWords, in: text)
        let receiptHits = wordHits(moneyWords, in: text) + bookingHits
        let barcode = features.barcodeCount > 0
        let textCode = textCodeScores(body, texts: texts, text: text, barcode: barcode)

        return [
            // A barcode next to booking or money words is a ticket or a receipt, not just a code.
            (.code, barcode ? (receiptHits >= 2 ? 0.55 : 0.9) : textCode.code),
            (.oneTimeCode, textCode.oneTime),
            (.receipt, max(receiptScore(rows: rowTexts, text: text), ticketScore(bookingHits: bookingHits, barcode: barcode))),
            (.chat, chatScore(body, text: text)),
            (.map, mapScore(features, text: text)),
            (.social, socialScore(text: text)),
            (.web, webScore(body, text: text)),
            (.document, documentScore(body, texts: texts)),
            (.photo, photoScore(features, body: body)),
        ]
    }

    // MARK: Scores

    /// A short message with one number in it. A code that dies in minutes is a one-time code. A secret or a code
    /// that stays valid (PIN, Wi-Fi password, recovery or pickup code) stays a plain code and is never suggested by age.
    /// A long page that mentions a code is neither.
    private static func textCodeScores(
        _ body: [RecognizedLine], texts: [String], text: String, barcode: Bool
    ) -> (code: Double, oneTime: Double) {
        guard !barcode, body.count <= 8, texts.contains(where: { matchCount(loneNumberPattern, in: $0) > 0 }) else {
            return (0, 0)
        }
        let secret = wordHits(secretWords, in: text) > 0
        let kept = secret || wordHits(keepWords, in: text) > 0
        let codeWord = hasCodeWord(text)
        if kept { return (codeWord || secret ? 0.7 : 0, 0) }
        return (0, codeWord ? 0.7 : 0)
    }

    private static func hasCodeWord(_ text: String) -> Bool {
        if wordHits(codeWords, in: text) > 0 { return true }
        // German and Hungarian join the word: "bestatigungscode".
        return text.split { !$0.isLetter }.map(String.init).contains {
            $0.count > 5 && ($0.hasSuffix("code") || $0.hasSuffix("kod")) && !notCodeCompounds.contains($0)
        }
    }

    private static func ticketScore(bookingHits: Int, barcode: Bool) -> Double {
        bookingHits >= 3 || (barcode && bookingHits >= 2) ? 0.6 : 0
    }

    /// Money words next to an amount on the same row: "Total 24,90 €". Prices alone, or a word alone, stay low.
    private static func receiptScore(rows: [String], text: String) -> Double {
        let moneyRows = rows.filter {
            wordHits(moneyWords, in: $0) > 0 && (matchCount(amountPattern, in: $0) > 0 || matchCount(bareDecimalPattern, in: $0) > 0)
        }.count
        let amounts = matchCount(amountPattern, in: text)
        let hits = wordHits(moneyWords, in: text)
        return min(0.6, Double(moneyRows) * 0.3) + min(0.2, Double(amounts) * 0.1) + min(0.2, Double(hits) * 0.1)
    }

    private static func chatScore(_ body: [RecognizedLine], text: String) -> Double {
        let times = matchCount(timePattern, in: text)
        let messages = body.filter(isMessageText)
        let rightSide = messages.filter { $0.minX > 0.35 && $0.maxX > 0.8 }
        let leftSide = messages.filter { $0.minX < 0.2 && $0.maxX < 0.75 }
        // A left and a right line on one row are table cells. Bubbles never share a row.
        let right = rightSide.filter { line in !leftSide.contains { sameRow($0, line) } }.count
        let left = leftSide.filter { line in !rightSide.contains { sameRow($0, line) } }.count
        var score = min(0.3, Double(times) * 0.15)
        if left >= 2, right >= 2 { score += 0.35 }
        return score + min(0.4, Double(wordHits(chatWords, in: text)) * 0.2)
    }

    /// Words, not a time, a price or a lone digit. A time inside the line ("Ok 12:44") does not count against it.
    private static func isMessageText(_ line: RecognizedLine) -> Bool {
        let words = line.text.replacingOccurrences(of: timePattern, with: " ", options: .regularExpression)
        let letters = words.filter(\.isLetter).count
        let digits = words.filter(\.isNumber).count
        return letters >= 2 && letters > digits
    }

    private static func sameRow(_ a: RecognizedLine, _ b: RecognizedLine) -> Bool {
        abs((a.minY + a.maxY) - (b.minY + b.maxY)) / 2 < rowTolerance
    }

    private static func mapScore(_ f: ScreenshotFeatures, text: String) -> Double {
        let measures = matchCount(#"\b\d+(?:[.,]\d+)?\s?(?:km|mi|m)\b|\b\d+\s?(?:min|h)\b"#, in: text)
        let words = wordHits(mapWords, in: text)
        let labelled = (f.labels["map"] ?? 0) >= 0.4
        guard labelled || words >= 2 else { return 0 }
        return min(0.5, Double(measures) * 0.25) + min(0.45, Double(words) * 0.15) + (labelled ? 0.5 : 0)
    }

    private static func socialScore(text: String) -> Double {
        var score = min(0.5, Double(wordHits(socialWords, in: text)) * 0.2)
        if matchCount(#"(?<![a-z0-9])@[a-z0-9_.]{3,}"#, in: text) > 0 { score += 0.3 }
        if matchCount(#"\b\d+(?:[.,]\d+)?\s?k\b"#, in: text) > 0 { score += 0.2 }
        return score
    }

    private static func webScore(_ body: [RecognizedLine], text: String) -> Double {
        var score = min(0.4, Double(wordHits(webWords, in: text)) * 0.1)
        if body.contains(where: isAddressLine) { score += 0.5 }
        return score
    }

    /// Safari shows just the domain, centred, in the bottom bar by default and at the top in the single tab layout.
    private static func isAddressLine(_ line: RecognizedLine) -> Bool {
        let atEdge = line.minY < 0.15 || line.minY > 0.85
        guard atEdge, (0.3...0.7).contains((line.minX + line.maxX) / 2) else { return false }
        return matchCount(#"^\W{0,3}(?:www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}(?:/\S*)?\W{0,3}$"#, in: fold(line.text)) > 0
    }

    private static func documentScore(_ body: [RecognizedLine], texts: [String]) -> Double {
        guard body.count >= 12 else { return 0 }
        let averageLength = Double(texts.reduce(0) { $0 + $1.count }) / Double(texts.count)
        guard averageLength >= 30 else { return 0 }
        let coverage = body.reduce(0) { $0 + ($1.maxX - $1.minX) * ($1.maxY - $1.minY) }
        return 0.6 + (coverage >= 0.25 ? 0.15 : 0)
    }

    private static func photoScore(_ f: ScreenshotFeatures, body: [RecognizedLine]) -> Double {
        guard body.count <= 5 else { return 0 }
        let strongest = f.labels.filter { !interfaceLabels.contains($0.key) }.values.max() ?? 0
        return strongest >= 0.5 ? 0.6 : 0
    }

    // MARK: Text helpers

    /// Lower case without accents, so "Objednávka" and "objednavka" are the same word.
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "ł", with: "l")
    }

    /// How many of the words or phrases appear. A single word must be a whole word.
    static func wordHits(_ words: [String], in text: String) -> Int {
        let tokens = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let set = Set(tokens)
        let padded = " " + tokens.joined(separator: " ") + " "
        return words.filter { $0.contains(" ") ? padded.contains(" \($0) ") : set.contains($0) }.count
    }

    /// Lines joined into rows by vertical centre, each row ordered left to right and folded.
    private static func rows(of body: [RecognizedLine]) -> [String] {
        var rows: [[RecognizedLine]] = []
        for line in body.sorted(by: { $0.minY + $0.maxY < $1.minY + $1.maxY }) {
            if let first = rows.last?.first, sameRow(first, line) {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.minX < $1.minX }.map { fold($0.text) }.joined(separator: " ") }
    }

    private static func matchCount(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
