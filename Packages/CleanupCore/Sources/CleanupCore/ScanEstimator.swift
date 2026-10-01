import Foundation

/// How many items each counted stage has to work through, known once the cache lookup is done.
public struct ScanWorkPlan: Equatable, Sendable {
    public var sizing: Int
    public var analyzing: Int
    public var reading: Int

    public init(sizing: Int, analyzing: Int, reading: Int) {
        self.sizing = sizing
        self.analyzing = analyzing
        self.reading = reading
    }
}

/// Seconds left in a scan, from the plan, the progress of the current stage and prior costs per item.
public enum ScanEstimator {
    /// Placeholders until stage times are measured on a phone. Sizing is the simulator figure (4.3 ms rounded up),
    /// reading is within the 50 to 100 ms range measured on a Mac.
    public static let sizingSecondsPerItem = 0.005
    public static let analyzingSecondsPerItem = 0.008
    public static let readingSecondsPerItem = 0.08
    public static let groupingSeconds = 1.0

    static let minItemsForObservedRate = 30
    static let minSecondsForObservedRate = 3.0
    static let minSecondsBeforeShowing = 3.0
    static let almostDoneBelow = 10.0
    static let aMinuteOrMore = 60.0
    static let roundToFiveAboveMinutes = 20.0

    private static func prior(for stage: ScanStage) -> Double {
        switch stage {
        case .sizing: sizingSecondsPerItem
        case .analyzing: analyzingSecondsPerItem
        case .reading: readingSecondsPerItem
        case .listing, .grouping: 0
        }
    }

    private static func pending(_ stage: ScanStage, in plan: ScanWorkPlan) -> Int {
        switch stage {
        case .sizing: plan.sizing
        case .analyzing: plan.analyzing
        case .reading: plan.reading
        case .listing, .grouping: 0
        }
    }

    /// `done` and `total` are the counts the stage reports. For analysing they include photos that were already
    /// cached, so the items finished in this scan are `done - (total - pending)`.
    /// `doneAtStageStart` is what the stage had reported when its first update arrived. Sizing reports in batches,
    /// so that first update already holds a batch whose time was never measured: the rate comes from the items
    /// finished since, over the time since.
    public static func secondsLeft(
        plan: ScanWorkPlan?, stage: ScanStage, done: Int, total: Int, secondsInStage: Double, doneAtStageStart: Int = 0
    ) -> Double? {
        guard let plan else { return nil }
        var left = 0.0
        for later in ScanStage.allCases where later.rawValue > stage.rawValue {
            left += later == .grouping ? groupingSeconds : Double(pending(later, in: plan)) * prior(for: later)
        }
        switch stage {
        case .listing:
            break
        case .grouping:
            left += max(groupingSeconds - secondsInStage, 0)
        case .sizing, .analyzing, .reading:
            let pending = pending(stage, in: plan)
            let finished = min(max(done - (total - pending), 0), pending)
            let finishedAtStart = min(max(doneAtStageStart - (total - pending), 0), finished)
            let observed = finished - finishedAtStart
            let hasEnoughData = observed > 0
                && (observed >= minItemsForObservedRate || secondsInStage >= minSecondsForObservedRate)
            let rate = hasEnoughData ? secondsInStage / Double(observed) : prior(for: stage)
            left += rate * Double(pending - finished)
        }
        return max(left, 0)
    }

    public static func text(secondsLeft: Double?, elapsed: Double) -> String {
        guard let secondsLeft, elapsed >= minSecondsBeforeShowing else { return "Estimating the time left" }
        if secondsLeft < almostDoneBelow { return "Almost done" }
        if secondsLeft < aMinuteOrMore { return "Less than a minute left" }
        let minutes = secondsLeft / 60
        let rounded = minutes > roundToFiveAboveMinutes ? (minutes / 5).rounded() * 5 : minutes.rounded()
        return "About \(Int(rounded)) min left"
    }
}

/// Keeps the shown value calm. It follows every fall at once. A higher estimate is approached over a few seconds
/// instead of jumped to, so the value neither flickers nor lags behind a stage that turns out slower than the prior.
public struct ScanTimeLeft: Sendable {
    /// Seconds in which the shown value covers about two thirds of the way to a higher estimate.
    public static let riseTimeConstant = 4.0

    private var shown: Double?
    private var lastElapsed = 0.0

    public init() {}

    public mutating func update(raw: Double?, elapsed: Double) -> Double? {
        guard let raw else { return shown }
        let target = max(raw, 0)
        defer { lastElapsed = elapsed }
        guard let previous = shown else {
            shown = target
            return target
        }
        let seconds = max(elapsed - lastElapsed, 0)
        let counted = max(previous - seconds, 0)
        let next = target <= counted ? target : counted + (target - counted) * (1 - exp(-seconds / Self.riseTimeConstant))
        shown = next
        return next
    }
}
