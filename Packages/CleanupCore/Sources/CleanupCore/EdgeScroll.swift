import Foundation

/// How fast a list scrolls while a finger that drags a selection sits near its top or bottom edge, as in the Photos
/// app: nothing until the finger enters the edge zone, faster the deeper it goes, full speed on the edge and beyond.
public enum EdgeScroll {
    public static let zone = 90.0
    public static let maxSpeed = 1_100.0

    /// Points per second to move the content: negative scrolls toward the top, positive toward the bottom.
    /// `y`, `top` and `bottom` share one space: the finger and the visible edges of the list.
    public static func velocity(y: Double, top: Double, bottom: Double) -> Double {
        let intoTop = top + zone - y
        if intoTop > 0 { return -maxSpeed * min(intoTop / zone, 1) }
        let intoBottom = y - (bottom - zone)
        if intoBottom > 0 { return maxSpeed * min(intoBottom / zone, 1) }
        return 0
    }
}
