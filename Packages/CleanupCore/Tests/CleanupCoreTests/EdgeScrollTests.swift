import Testing
@testable import CleanupCore

@Suite struct EdgeScrollTests {
    @Test func staysStillAwayFromTheEdges() {
        #expect(EdgeScroll.velocity(y: 400, top: 100, bottom: 800) == 0)
        #expect(EdgeScroll.velocity(y: 100 + EdgeScroll.zone, top: 100, bottom: 800) == 0)
        #expect(EdgeScroll.velocity(y: 800 - EdgeScroll.zone, top: 100, bottom: 800) == 0)
    }

    @Test func speedGrowsWithTheDepthIntoTheBottomZone() {
        let shallow = EdgeScroll.velocity(y: 800 - EdgeScroll.zone + 10, top: 100, bottom: 800)
        let half = EdgeScroll.velocity(y: 800 - EdgeScroll.zone / 2, top: 100, bottom: 800)
        #expect(shallow > 0 && shallow < half)
        #expect(abs(half - EdgeScroll.maxSpeed / 2) < 1e-9)
        #expect(EdgeScroll.velocity(y: 800, top: 100, bottom: 800) == EdgeScroll.maxSpeed)
    }

    @Test func scrollsTowardTheTopNearTheTopEdge() {
        let half = EdgeScroll.velocity(y: 100 + EdgeScroll.zone / 2, top: 100, bottom: 800)
        #expect(abs(half + EdgeScroll.maxSpeed / 2) < 1e-9)
        #expect(EdgeScroll.velocity(y: 100, top: 100, bottom: 800) == -EdgeScroll.maxSpeed)
    }

    @Test func aFingerBeyondTheEdgeScrollsAtFullSpeedNoFaster() {
        #expect(EdgeScroll.velocity(y: 2_000, top: 100, bottom: 800) == EdgeScroll.maxSpeed)
        #expect(EdgeScroll.velocity(y: -500, top: 100, bottom: 800) == -EdgeScroll.maxSpeed)
    }
}
