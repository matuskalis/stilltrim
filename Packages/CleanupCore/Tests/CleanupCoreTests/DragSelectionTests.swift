import Testing
@testable import CleanupCore

@Suite struct DragSelectionTests {
    private let order = ["a", "b", "c", "d", "e"]

    @Test func forwardDragSelectsTheRunIncludingBothEnds() {
        let drag = DragSelection(order: order, startSelection: [], anchor: "b")
        #expect(drag.mode == .select)
        #expect(drag.selection(through: "d") == ["b", "c", "d"])
    }

    @Test func backwardDragSelectsTheSameRun() {
        let drag = DragSelection(order: order, startSelection: [], anchor: "d")
        #expect(drag.selection(through: "b") == ["b", "c", "d"])
    }

    @Test func movingBackUndoesCellsAndPassingTheAnchorSwitchesSide() {
        let drag = DragSelection(order: order, startSelection: ["a"], anchor: "c")
        #expect(drag.selection(through: "e") == ["a", "c", "d", "e"])
        #expect(drag.selection(through: "d") == ["a", "c", "d"])
        #expect(drag.selection(through: "c") == ["a", "c"])
        #expect(drag.selection(through: "a") == ["a", "b", "c"])
    }

    @Test func anchorOnASelectedCellDeselectsTheRunAndLeavesTheRest() {
        let drag = DragSelection(order: order, startSelection: ["a", "b", "c", "e"], anchor: "b")
        #expect(drag.mode == .deselect)
        #expect(drag.selection(through: "d") == ["a", "e"])
        #expect(drag.selection(through: "b") == ["a", "c", "e"])
    }

    @Test func singleCellDragSetsJustThatCell() {
        #expect(DragSelection(order: order, startSelection: [], anchor: "c").selection(through: "c") == ["c"])
        #expect(DragSelection(order: order, startSelection: ["c"], anchor: "c").selection(through: "c") == [])
    }

    @Test func unknownCurrentCellChangesNothing() {
        let drag = DragSelection(order: order, startSelection: ["a"], anchor: "b")
        #expect(drag.selection(through: "zzz") == ["a"])
    }

    @Test func unknownAnchorChangesNothing() {
        let drag = DragSelection(order: order, startSelection: ["a"], anchor: "zzz")
        #expect(drag.selection(through: "c") == ["a"])
    }

    @Test func idsOutsideTheOrderAreNeverTouched() {
        let drag = DragSelection(order: order, startSelection: ["elsewhere"], anchor: "a")
        #expect(drag.selection(through: "e") == ["elsewhere", "a", "b", "c", "d", "e"])
        let deselecting = DragSelection(order: order, startSelection: ["elsewhere", "a"], anchor: "a")
        #expect(deselecting.selection(through: "c") == ["elsewhere"])
    }

    @Test func emptyOrderChangesNothing() {
        let drag = DragSelection(order: [], startSelection: ["x"], anchor: "x")
        #expect(drag.selection(through: "x") == ["x"])
    }

    @Test func selectingSkipsIdsThatMayNotBeSelectedAndDeselectingClearsThem() {
        let select = DragSelection(order: order, startSelection: [], anchor: "a", selectable: ["a", "b", "d", "e"])
        #expect(select.selection(through: "e") == ["a", "b", "d", "e"])

        let deselect = DragSelection(order: order, startSelection: ["a", "c", "e"], anchor: "a", selectable: ["a", "b"])
        #expect(deselect.mode == .deselect)
        #expect(deselect.selection(through: "e").isEmpty)
    }
}
