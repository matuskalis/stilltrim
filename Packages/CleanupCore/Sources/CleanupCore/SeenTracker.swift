/// Which photos the user had on screen long enough to see, so "delete above" never counts rows that a
/// flick only passed. Pure: the list reports when a photo is on screen and when it went past the top edge.
public struct SeenTracker: Sendable {
    /// How long a photo must take to cross the visible area, from entering it to leaving through the top.
    /// This is transit time, not reading time: at 800 pt/s or slower (a visible height of about 600 pt plus a
    /// row of about 130 pt gives roughly 0.9 s) the user can take the photo in, a hard flick of 2,500 pt/s
    /// crosses in about 0.3 s. A stand-in until measured on a phone; tune it here.
    public static let minimumTransit = Duration.seconds(1)

    public private(set) var seen: Set<String> = []
    private var onScreenSince: [String: ContinuousClock.Instant] = [:]

    public init() {}

    /// The photo entered the visible area. Repeated reports keep the first time; a seen photo that re-enters starts over.
    public mutating func appeared(_ id: String, at instant: ContinuousClock.Instant) {
        seen.remove(id)
        if onScreenSince[id] == nil { onScreenSince[id] = instant }
    }

    /// The photo left through the top. It counts only if its transit took at least `minimumTransit`.
    public mutating func scrolledPast(_ id: String, at instant: ContinuousClock.Instant) {
        guard let since = onScreenSince.removeValue(forKey: id) else { return }
        if instant - since >= Self.minimumTransit { seen.insert(id) }
    }

    /// The photo left without passing the top (below the screen, or dropped by the list). It is not seen.
    public mutating func disappeared(_ id: String) {
        onScreenSince.removeValue(forKey: id)
    }
}
