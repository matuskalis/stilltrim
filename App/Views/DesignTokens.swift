import CleanupCore
import SwiftUI
import UIKit

/// Colours and sizes the screens share. The accent comes from the asset catalog; nothing else is invented.
enum DesignTokens {
    static let accent = Color.accentColor

    /// White check on the light accent, black on the lighter dark accent (both 4.5:1 or better).
    static let onAccent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .black : .white })

    enum Mark {
        static let diameter = CGFloat(SelectionMarkSpec.diameter)
        static let ringWidth = CGFloat(SelectionMarkSpec.ringWidth)
        static let keylineWidth = CGFloat(SelectionMarkSpec.keylineWidth)
        static let ring = Color.white
        static let disc = Color.black.opacity(SelectionMarkSpec.discScrimOpacity)
        static let keyline = Color.black.opacity(SelectionMarkSpec.keylineOpacity)
        static let selectedPhotoScale = CGFloat(SelectionMarkSpec.selectedPhotoScale)
    }

    enum Pill {
        static let scrim = Color.black.opacity(SelectionMarkSpec.pillScrimOpacity)
        static let text = Color.white
    }
}
