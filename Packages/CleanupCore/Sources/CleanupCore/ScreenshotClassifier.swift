import Foundation

public enum ScreenshotKind: String, CaseIterable, Sendable, Codable {
    case chat, receipt, code, map, web, social, document, photo, recording, mix
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
    public static let version = 1

    private static let minimumScore = 0.5
    /// Clock, signal and battery live above this line, the home indicator below the other.
    private static let statusBarBottom = 0.06
    private static let homeIndicatorTop = 0.97

    private static let receiptWords = [
        "total", "subtotal", "tax", "vat", "order", "invoice", "receipt", "payment", "paid", "ticket",
        "boarding", "gate", "seat", "flight", "booking", "confirmation", "reservation", "amount",
        "objednavka", "faktura", "uctenka", "letenka", "listok", "rezervacia", "platba", "celkom", "suma",
        "dph", "medzisucet", "potvrdenie", "objednavku",
    ]
    private static let chatWords = [
        "delivered", "read", "seen", "typing", "imessage", "whatsapp", "type a message", "message",
        "sprava", "napiste", "dorucene", "precitane",
    ]
    private static let mapWords = [
        "directions", "route", "navigate", "eta", "arrive", "traffic", "start", "trasa", "navigovat",
    ]
    private static let webWords = [
        "cookie", "cookies", "accept", "subscribe", "sign in", "read more", "advertisement",
        "privacy policy", "prijat", "suhlasim",
    ]
    private static let socialWords = [
        "likes", "comments", "share", "followers", "following", "reply", "retweet", "repost", "reels",
        "story", "views", "follow", "sledovatelov", "odpovedat", "zdielat",
    ]
    private static let codeWords = ["code", "verification", "otp", "kod", "overenie", "heslo", "password", "pin"]
    private static let interfaceLabels: Set<String> = [
        "screenshot", "document", "map", "chart", "diagram", "flipchart", "book", "checkbook", "computer",
        "computer_monitor", "credit_card", "gift_card", "poster", "menu", "whiteboard", "blackboard",
        "newspaper", "magazine", "paper", "sign", "font", "text", "web_site",
    ]

    public static func classify(_ features: ScreenshotFeatures) -> ScreenshotKind {
        let body = features.lines.filter { $0.minY >= statusBarBottom && $0.maxY <= homeIndicatorTop }
        let texts = body.map { fold($0.text) }
        let text = texts.joined(separator: "\n")
        let receiptHits = wordHits(receiptWords, in: text)

        // Fixed order, so a tie is always settled the same way.
        let scores: [(ScreenshotKind, Double)] = [
            (.code, codeScore(features, texts: texts, text: text, receiptHits: receiptHits)),
            (.receipt, receiptScore(text: text, hits: receiptHits)),
            (.chat, chatScore(body, text: text)),
            (.map, mapScore(features, text: text)),
            (.social, socialScore(text: text)),
            (.web, webScore(body, text: text)),
            (.document, documentScore(body, texts: texts)),
            (.photo, photoScore(features, body: body)),
        ]
        var best: (kind: ScreenshotKind, score: Double) = (.mix, 0)
        for (kind, score) in scores where score > best.score { best = (kind, score) }
        return best.score >= minimumScore ? best.kind : .mix
    }

    // MARK: Scores

    private static func codeScore(_ f: ScreenshotFeatures, texts: [String], text: String, receiptHits: Int) -> Double {
        var score = 0.0
        // A barcode next to booking words is a ticket, not just a code.
        if f.barcodeCount > 0 { score = receiptHits >= 2 ? 0.55 : 0.9 }
        let digitsOnly = texts.contains { matchCount(#"^\D*\d{4,8}\D*$"#, in: $0) > 0 }
        if digitsOnly, wordHits(codeWords, in: text) > 0 { score = max(score, 0.7) }
        return score
    }

    private static func receiptScore(text: String, hits: Int) -> Double {
        let amounts = matchCount(
            #"[€$£]\s?\d{1,3}(?:[ .,]\d{3})*(?:[.,]\d{2})?|\d{1,3}(?:[ .,]\d{3})*[.,]\d{2}\s?(?:€|\$|£|eur|usd|czk|kc)"#,
            in: text
        )
        return min(0.45, Double(amounts) * 0.2) + min(0.6, Double(hits) * 0.2)
    }

    private static func chatScore(_ body: [RecognizedLine], text: String) -> Double {
        let times = matchCount(#"\b(?:[01]?\d|2[0-3]):[0-5]\d\b"#, in: text)
        let right = body.filter { $0.minX > 0.35 && $0.maxX > 0.8 }.count
        let left = body.filter { $0.minX < 0.2 && $0.maxX < 0.75 }.count
        var score = times >= 3 ? 0.3 : 0
        if left >= 2, right >= 2 { score += 0.35 }
        return score + min(0.4, Double(wordHits(chatWords, in: text)) * 0.2)
    }

    private static func mapScore(_ f: ScreenshotFeatures, text: String) -> Double {
        let measures = matchCount(#"\b\d+(?:[.,]\d+)?\s?(?:km|mi|m)\b|\b\d+\s?(?:min|h)\b"#, in: text)
        var score = min(0.5, Double(measures) * 0.25) + min(0.45, Double(wordHits(mapWords, in: text)) * 0.15)
        if (f.labels["map"] ?? 0) >= 0.4 { score += 0.5 }
        return score
    }

    private static func socialScore(text: String) -> Double {
        var score = min(0.5, Double(wordHits(socialWords, in: text)) * 0.2)
        if matchCount(#"(?<![a-z0-9])@[a-z0-9_.]{3,}"#, in: text) > 0 { score += 0.3 }
        if matchCount(#"\b\d+(?:[.,]\d+)?\s?k\b"#, in: text) > 0 { score += 0.2 }
        return score
    }

    private static func webScore(_ body: [RecognizedLine], text: String) -> Double {
        let top = body.filter { $0.minY < 0.15 }.map { fold($0.text) }.joined(separator: "\n")
        var score = min(0.4, Double(wordHits(webWords, in: text)) * 0.1)
        if matchCount(#"\b[a-z0-9-]+\.(?:com|org|net|sk|cz|io|co|app|de|uk|eu|info|news)\b"#, in: top) > 0 { score += 0.5 }
        return score
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
    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// How many of the words or phrases appear. A single word must be a whole word.
    private static func wordHits(_ words: [String], in text: String) -> Int {
        let tokens = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return words.filter { $0.contains(" ") ? text.contains($0) : tokens.contains($0) }.count
    }

    private static func matchCount(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
