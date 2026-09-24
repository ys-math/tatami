import CoreGraphics
import Testing

@testable import TatamiCore

private func cells(_ column: Int, _ row: Int, _ columns: Int, _ rows: Int) -> CGRect {
    gappedGrid.rect(for: CellSpan(column: column, row: row, columnCount: columns, rowCount: rows))
}

/// A B C in the top row, D spanning the bottom row.
private let layout = [
    "A": cells(0, 0, 1, 1), "B": cells(1, 0, 1, 1), "C": cells(2, 0, 2, 1), "D": cells(0, 1, 4, 1),
]

struct WindowModeStateTests {
    private func makeState() -> WindowModeState<String> {
        WindowModeState(frames: layout)!
    }

    @Test func labelsFollowReadingOrderAndSkipCommandKeys() {
        let state = makeState()
        #expect(state.windows == ["A", "B", "C", "D"])
        #expect(state.label(of: "A") == "a" && state.label(of: "D") == "f")
        let reserved = WindowModeState<String>.reservedKeys
        let many = WindowModeState(
            frames: Dictionary(
                uniqueKeysWithValues: (0..<40).map {
                    ("W\($0)", CGRect(x: $0 * 10, y: 0, width: 5, height: 5))
                }))!
        #expect(many.labels.allSatisfy { $0.allSatisfy { !reserved.contains($0) } })
        #expect(Set(many.labels).count == 40)
    }

    @Test func labelsToggleSelection() {
        var state = makeState()
        #expect(state.handle(.character("a")) == .updated)
        #expect(state.handle(.character("F")) == .updated)  // D's label, typed in upper case.
        #expect(state.selected == ["A", "D"])
        #expect(state.handle(.character("a")) == .updated)
        #expect(state.selected == ["D"])
        #expect(state.handle(.character("z")) == .ignored)
    }

    @Test func rotateUsesTheSelectionWhenThereIsOne() {
        var state = makeState()
        #expect(state.handle(.rotate(clockwise: true)) == .action(.rotateClockwise))
        #expect(state.handle(.rotate(clockwise: false)) == .action(.rotateCounterclockwise))
        _ = state.handle(.character("a"))
        #expect(state.handle(.rotate(clockwise: true)) == .ignored)  // One window: nothing to rotate with.
        _ = state.handle(.character("s"))
        #expect(state.handle(.rotate(clockwise: true)) == .rotateGroup(["A", "B"], clockwise: true))
    }

    @Test func swapAndMainActOnTheFocusedWindow() {
        var state = makeState()
        #expect(state.handle(.swap(.right)) == .action(.swapRight))
        #expect(state.handle(.swap(.up)) == .action(.swapUp))
        #expect(state.handle(.swapWithMain) == .action(.swapWithMain))
    }

    @Test func staysOpenUntilExit() {
        var state = makeState()
        _ = state.handle(.swap(.left))
        _ = state.handle(.rotate(clockwise: true))
        #expect(state.handle(.exit) == .exit)
    }

    @Test func refreshKeepsLabelsWithTheirWindows() {
        var state = makeState()
        _ = state.handle(.character("a"))
        var moved = layout
        moved["A"] = layout["B"]
        moved["B"] = layout["A"]
        moved["D"] = nil
        state.refresh(frames: moved)
        #expect(state.label(of: "A") == "a")
        #expect(state.frames["A"] == layout["B"])
        #expect(state.selected == ["A"])
        #expect(state.frames["D"] == nil)
    }

    @Test func noWindowsNoMode() {
        #expect(WindowModeState<String>(frames: [:]) == nil)
    }
}
