import CoreGraphics
import Testing

@testable import TatamiCore

private func span(_ column: Int, _ row: Int, _ columns: Int, _ rows: Int) -> CellSpan {
    CellSpan(column: column, row: row, columnCount: columns, rowCount: rows)
}

struct GridLabelsTests {
    @Test func defaultGridUsesKeyboardShape() {
        #expect(GridLabels.labels(for: .default) == ["q", "w", "e", "r", "a", "s", "d", "f"])
    }

    @Test(arguments: [GridSize(columns: 6, rows: 2), GridSize(columns: 4, rows: 5), GridSize(columns: 8, rows: 4)])
    func largerGridsUseSingleCharacters(size: GridSize) {
        let labels = GridLabels.labels(for: size)
        #expect(labels.count == size.cellCount)
        #expect(Set(labels).count == labels.count)
        #expect(labels.allSatisfy { $0.count == 1 })
    }

    @Test func hugeGridsUseTwoCharacterLabels() {
        let size = GridSize(columns: 24, rows: 24)
        let labels = GridLabels.labels(for: size)
        #expect(labels.count == 576)
        #expect(Set(labels).count == 576)
        #expect(labels.allSatisfy { $0.count == 2 })
    }

    @Test(arguments: [GridSize.default, GridSize(columns: 10, rows: 3), GridSize(columns: 24, rows: 24)])
    func labelsAvoidReservedKeys(size: GridSize) {
        let reserved: Set<Character> = ["h", "j", "k", "l", "-", "=", "_", "+"]
        #expect(GridLabels.labels(for: size).allSatisfy { $0.allSatisfy { !reserved.contains($0) } })
    }
}

struct SpanCommandsTests {
    let size = GridSize(columns: 4, rows: 2)

    @Test func resizeUsesTheTmuxRule() {
        // Inner right edge moves.
        #expect(GridCommands.resize(span(0, 0, 2, 1), .right, in: size) == span(0, 0, 3, 1))
        #expect(GridCommands.resize(span(0, 0, 2, 1), .left, in: size) == span(0, 0, 1, 1))
        // At the right side: the left edge moves.
        #expect(GridCommands.resize(span(2, 0, 2, 1), .left, in: size) == span(1, 0, 3, 1))
        #expect(GridCommands.resize(span(2, 0, 2, 1), .right, in: size) == span(3, 0, 1, 1))
        // Full width shrinks from the far edge.
        #expect(GridCommands.resize(span(0, 0, 4, 1), .left, in: size) == span(0, 0, 3, 1))
        #expect(GridCommands.resize(span(0, 0, 4, 1), .right, in: size) == span(1, 0, 3, 1))
        // Vertical.
        #expect(GridCommands.resize(span(0, 0, 1, 1), .down, in: size) == span(0, 0, 1, 2))
        #expect(GridCommands.resize(span(0, 0, 1, 2), .down, in: size) == span(0, 1, 1, 1))
    }

    @Test func resizeNeverEmptiesASpan() {
        #expect(GridCommands.resize(span(0, 0, 1, 1), .left, in: size) == nil)
        #expect(GridCommands.resize(span(3, 0, 1, 1), .right, in: size) == nil)
    }

    @Test func mapKeepsProportions() {
        let from = GridSize(columns: 4, rows: 2)
        #expect(GridCommands.map(span(0, 0, 2, 2), from: from, to: GridSize(columns: 6, rows: 3)) == span(0, 0, 3, 3))
        #expect(GridCommands.map(span(2, 1, 2, 1), from: from, to: GridSize(columns: 2, rows: 1)) == span(1, 0, 1, 1))
        #expect(GridCommands.map(span(3, 0, 1, 1), from: from, to: GridSize(columns: 1, rows: 1)) == span(0, 0, 1, 1))
    }

    @Test func unionCoversBothCorners() {
        #expect(span(3, 1, 1, 1).union(span(1, 0, 1, 1)) == span(1, 0, 3, 2))
    }
}

struct GridModeStateTests {
    private func state(sizes: [GridSize] = [.default], selection: CellSpan = span(0, 0, 1, 1)) -> GridModeState {
        GridModeState(displayIndex: 0, gridSizes: sizes, selection: selection)
    }

    @Test func twoLabelsApplyTheSpanBetweenThem() {
        var state = state()
        #expect(state.handle(.character("w")) == .updated)
        #expect(state.corner == span(1, 0, 1, 1))
        #expect(state.selection == span(1, 0, 1, 1))
        #expect(state.handle(.character("F")) == .apply(displayIndex: 0, span(1, 0, 3, 2)))
    }

    @Test func returnAfterOneLabelAppliesThatCell() {
        var state = state()
        _ = state.handle(.character("d"))
        #expect(state.handle(.apply) == .apply(displayIndex: 0, span(2, 1, 1, 1)))
    }

    @Test func unknownLabelIsIgnored() {
        var state = state()
        #expect(state.handle(.character("z")) == .ignored)
        #expect(state.corner == nil)
    }

    @Test func twoCharacterLabelsNeedBothKeys() {
        var state = state(sizes: [GridSize(columns: 24, rows: 24)])
        #expect(state.handle(.character("a")) == .updated)
        #expect(state.typed == "a")
        #expect(state.corner == nil)
        #expect(state.handle(.character("s")) == .updated)
        #expect(state.corner == span(1, 0, 1, 1))
        #expect(state.typed == "")
    }

    @Test func cursorMovesAndResizes() {
        var state = state()
        #expect(state.handle(.move(.right)) == .updated)
        #expect(state.handle(.resize(.right)) == .updated)
        #expect(state.handle(.resize(.down)) == .updated)
        #expect(state.selection == span(1, 0, 2, 2))
        #expect(state.handle(.move(.up)) == .ignored)
        #expect(state.handle(.apply) == .apply(displayIndex: 0, span(1, 0, 2, 2)))
    }

    @Test func cursorInputClearsAPendingCorner() {
        var state = state()
        _ = state.handle(.character("q"))
        _ = state.handle(.move(.right))
        #expect(state.corner == nil)
        // The next label starts a new span instead of completing the old one.
        #expect(state.handle(.character("r")) == .updated)
    }

    @Test func adjustingTheGridRemapsTheSelection() {
        var state = state(selection: span(0, 0, 2, 2))
        #expect(
            state.handle(.adjustGrid(columns: 2, rows: 0))
                == .gridChanged(displayIndex: 0, GridSize(columns: 6, rows: 2)))
        #expect(state.selection == span(0, 0, 3, 2))
        #expect(
            state.handle(.adjustGrid(columns: 0, rows: -5))
                == .gridChanged(displayIndex: 0, GridSize(columns: 6, rows: 1)))
        #expect(state.handle(.adjustGrid(columns: 0, rows: -1)) == .ignored)
    }

    @Test func tabMovesToTheNextDisplayProportionally() {
        var state = state(sizes: [.default, GridSize(columns: 6, rows: 3)], selection: span(2, 0, 2, 2))
        #expect(state.handle(.nextDisplay) == .updated)
        #expect(state.displayIndex == 1)
        #expect(state.selection == span(3, 0, 3, 3))
        #expect(state.handle(.nextDisplay) == .updated)
        #expect(state.displayIndex == 0)
        #expect(state.handle(.apply) == .apply(displayIndex: 0, span(2, 0, 2, 2)))
    }

    @Test func tabWithOneDisplayIsIgnored() {
        var state = state()
        #expect(state.handle(.nextDisplay) == .ignored)
    }

    @Test func cancel() {
        var state = state()
        #expect(state.handle(.cancel) == .cancel)
    }
}

struct DisplayOrderTests {
    @Test func sortsLeftToRightThenTopToBottom() {
        func display(_ id: String, _ x: CGFloat, _ y: CGFloat) -> Display {
            let frame = CGRect(x: x, y: y, width: 100, height: 100)
            return Display(id: id, frame: frame, visibleFrame: frame)
        }
        let sorted = Display.sortedPhysically([
            display("right", 1000, 0), display("main", 0, 0), display("left", -800, 200), display("below", 0, 900),
        ])
        #expect(sorted.map(\.id) == ["left", "main", "below", "right"])
    }
}
