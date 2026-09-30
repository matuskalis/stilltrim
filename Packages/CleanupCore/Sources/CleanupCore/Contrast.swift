import Foundation

/// WCAG 2.x contrast maths and the selection mark constants the app draws and the tests check.
public enum Contrast {
    /// Relative luminance of an sRGB colour, components 0...1.
    public static func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public static func ratio(_ a: (red: Double, green: Double, blue: Double), _ b: (red: Double, green: Double, blue: Double)) -> Double {
        let la = luminance(red: a.red, green: a.green, blue: a.blue)
        let lb = luminance(red: b.red, green: b.green, blue: b.blue)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

/// Selection mark geometry and opacities. The app's `DesignTokens` reads these, so the tests and the screen agree.
public enum SelectionMarkSpec {
    public static let diameter = 22.0
    public static let ringWidth = 2.0
    public static let keylineWidth = 1.0
    /// Black disc behind the mark, under the white ring.
    public static let discScrimOpacity = 0.22
    /// Black keyline outside the white ring.
    public static let keylineOpacity = 0.6
    /// Black capsule behind badge pills, white text on top.
    public static let pillScrimOpacity = 0.6
    /// Selected photos shrink to show the page around them: a shape cue beside colour.
    public static let selectedPhotoScale = 0.9
}
