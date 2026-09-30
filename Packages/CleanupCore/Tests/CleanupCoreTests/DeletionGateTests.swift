import Foundation
import Testing
@testable import CleanupCore

@Suite struct DeletionGateTests {
    private let edited = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    private func state(_ date: Date?, favorite: Bool = false) -> AssetSnapshot {
        AssetSnapshot(modificationDate: date, isFavorite: favorite)
    }

    @Test func unchangedPhotoMayBeDeleted() {
        let outcome = DeletionGate.partition(
            requested: ["a"], scanned: ["a": state(edited)], current: ["a": state(edited)])
        #expect(outcome.allowed == ["a"])
        #expect(outcome.changed.isEmpty)
    }

    @Test func newModificationDateMeansChanged() {
        let outcome = DeletionGate.partition(
            requested: ["a"], scanned: ["a": state(edited)], current: ["a": state(later)])
        #expect(outcome.allowed.isEmpty)
        #expect(outcome.changed == ["a"])
    }

    @Test func toggledFavouriteMeansChangedEvenWithTheSameDate() {
        let outcome = DeletionGate.partition(
            requested: ["a"], scanned: ["a": state(edited)], current: ["a": state(edited, favorite: true)])
        #expect(outcome.allowed.isEmpty)
        #expect(outcome.changed == ["a"])
    }

    @Test func missingPhotoIsNeitherAllowedNorChanged() {
        let outcome = DeletionGate.partition(requested: ["a"], scanned: ["a": state(edited)], current: [:])
        #expect(outcome.allowed.isEmpty)
        #expect(outcome.changed.isEmpty)
    }

    @Test func photoWithoutScannedStateIsChanged() {
        let outcome = DeletionGate.partition(requested: ["a"], scanned: [:], current: ["a": state(edited)])
        #expect(outcome.allowed.isEmpty)
        #expect(outcome.changed == ["a"])
    }

    @Test func mixedBatchIsSplitPerPhoto() {
        let outcome = DeletionGate.partition(
            requested: ["same", "moved", "fav", "gone", "unknown"],
            scanned: ["same": state(edited), "moved": state(edited), "fav": state(edited), "gone": state(edited)],
            current: ["same": state(edited), "moved": state(later), "fav": state(edited, favorite: true),
                      "unknown": state(edited), "other": state(edited)])
        #expect(outcome.allowed == ["same"])
        #expect(outcome.changed == ["moved", "fav", "unknown"])
    }

    @Test func emptyRequestChangesNothing() {
        let outcome = DeletionGate.partition(requested: [], scanned: ["a": state(edited)], current: ["a": state(edited)])
        #expect(outcome.allowed.isEmpty)
        #expect(outcome.changed.isEmpty)
    }

    @Test func itemBuiltWithoutModificationDateIsUnverifiable() {
        let item = CleanupItem(id: "a", byteSize: 1, creationDate: .distantPast)
        let result = ScanResult(screenshots: [item])
        let outcome = DeletionGate.partition(
            requested: ["a"], scanned: result.snapshots, current: ["a": state(edited)])
        #expect(outcome.allowed.isEmpty)
        #expect(outcome.changed == ["a"])
    }

    @Test func itemWithMatchingDateAndFlagPasses() {
        let item = CleanupItem(
            id: "a", byteSize: 1, creationDate: .distantPast, modificationDate: edited, isFavorite: true)
        let result = ScanResult(lowQuality: [item])
        let outcome = DeletionGate.partition(
            requested: ["a"], scanned: result.snapshots, current: ["a": state(edited, favorite: true)])
        #expect(outcome.allowed == ["a"])
    }
}
