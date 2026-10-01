/// What was deleted since the app launched, for the receipt after a delete.
public struct SessionTally: Equatable, Sendable {
    public private(set) var count = 0
    public private(set) var bytes: Int64 = 0
    public private(set) var batches = 0

    public init() {}

    public func adding(count added: Int, bytes addedBytes: Int64) -> SessionTally {
        var next = self
        next.count += added
        next.bytes += addedBytes
        next.batches += 1
        return next
    }
}
