import Foundation

public enum ByteFormat {
    /// One style for every size: decimal units, no-break space, nil when there is nothing to show.
    public static func size(_ bytes: Int64, locale: Locale = .current) -> String? {
        guard bytes > 0 else { return nil }
        let style = ByteCountFormatStyle(
            style: .file, allowedUnits: .default, spellsOutZero: false, includesActualByteCount: false, locale: locale
        )
        return bytes.formatted(style).replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}
