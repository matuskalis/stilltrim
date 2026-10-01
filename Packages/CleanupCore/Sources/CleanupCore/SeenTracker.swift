/// Which photos the user had on screen long enough to see, so "delete above" never counts rows that a
/// flick only passed. Pure: the list reports when a photo is on screen and when it went past the top edge.
public struct SeenTracker: Sendable {
    /// How long a photo must stay on screen before it counts as seen. A flick keeps a row on screen for
    /// about a fifth of a second and reading starts well above that. A stand-in until measured on a device.
    public static let dwell = Duration.milliseconds(250)

    public private(set) var seen: Set<String> = []
    private var onScreenSince: [String: ContinuousClock.Instant] = [:]

    public init() {}

    /// The photo is on screen. Repeated reports keep the first time; a seen photo that comes back starts over.
    public mutating func appeared(_ id: String, at instant: ContinuousClock.Instant) {
        seen.remove(id)
        if onScreenSince[id] == nil { onScreenSince[id] = instant }
    }

    /// The photo left through the top. It counts only if it was on screen for the dwell time before.
    public mutating func scrolledPast(_ id: String, at instant: ContinuousClock.Instant) {
        guard let since = onScreenSince.removeValue(forKey: id) else { return }
        if instant - since >= Self.dwell { seen.insert(id) }
    }

    /// The photo left without passing the top (below the screen, or dropped by the list). It is not seen.
    public mutating func disappeared(_ id: String) {
        onScreenSince.removeValue(forKey: id)
    }
}
