import CoreGraphics
import Testing

@testable import TatamiCore

private func display(_ id: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Display {
    let frame = CGRect(x: x, y: y, width: width, height: height)
    return Display(id: id, frame: frame, visibleFrame: frame)
}

struct AdjacentDisplayTests {
    let main = display("main", 0, 0, 1440, 900)
    let right = display("right", 1440, -200, 2560, 1440)
    let above = display("above", 200, -1080, 1920, 1080)
    let farLeft = display("farLeft", -3000, 2000, 1000, 800)

    @Test func findsTheDisplayInEachDirection() {
        let all = [main, right, above, farLeft]
        #expect(Display.adjacent(to: main, .right, in: all)?.id == "right")
        #expect(Display.adjacent(to: main, .up, in: all)?.id == "above")
        #expect(Display.adjacent(to: right, .left, in: all)?.id == "main")
        #expect(Display.adjacent(to: main, .down, in: all) == nil)
    }

    @Test func diagonalOnlyDisplayIsNotAdjacent() {
        #expect(Display.adjacent(to: main, .left, in: [main, farLeft]) == nil)
        #expect(Display.adjacent(to: main, .down, in: [main, farLeft]) == nil)
    }

    @Test func nearestSharedEdgeWins() {
        let near = display("near", 1440, 0, 800, 400)
        let far = display("far", 3000, 0, 1000, 900)
        #expect(Display.adjacent(to: main, .right, in: [main, far, near])?.id == "near")
    }
}

struct CrossTests {
    let from = GridSize(columns: 4, rows: 2)
    let to = GridSize(columns: 6, rows: 3)

    private func span(_ column: Int, _ row: Int, _ columns: Int, _ rows: Int) -> CellSpan {
        CellSpan(column: column, row: row, columnCount: columns, rowCount: rows)
    }

    @Test func entersAtTheNearEdgeKeepingWidth() {
        // Right column, bottom row → leftmost column, bottom third-ish, still one column wide.
        #expect(GridCommands.cross(span(3, 1, 1, 1), .right, from: from, to: to) == span(0, 2, 1, 1))
        // Moving left enters at the right edge.
        #expect(GridCommands.cross(span(0, 0, 2, 2), .left, from: from, to: to) == span(4, 0, 2, 3))
    }

    @Test func verticalCrossingMapsColumns() {
        #expect(GridCommands.cross(span(2, 0, 2, 1), .up, from: from, to: to) == span(3, 2, 3, 1))
    }

    @Test func clampsToASmallerGrid() {
        let tiny = GridSize(columns: 1, rows: 1)
        #expect(GridCommands.cross(span(1, 0, 3, 2), .right, from: from, to: tiny) == span(0, 0, 1, 1))
    }
}
