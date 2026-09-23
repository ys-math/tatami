import CoreGraphics
import Testing

@testable import TatamiCore

/// Uses `gappedGrid` (GridTests.swift): 4x2, 250pt cells, 10pt gaps.
/// Column x ranges: 100–350, 360–610, 620–870, 880–1130. Row y ranges: 50–300, 310–560.
/// Lines between columns sit at x = 355, 615, 875; between rows at y = 305.
struct BoundariesTests {
    let grid = gappedGrid
    let noMinimum = CGSize.zero

    private func span(_ column: Int, _ row: Int, _ columns: Int, _ rows: Int) -> CGRect {
        grid.rect(for: CellSpan(column: column, row: row, columnCount: columns, rowCount: rows))
    }

    // MARK: Joined resize

    @Test func twoHalvesMoveTogether() throws {
        let frames = ["A": span(0, 0, 2, 2), "B": span(2, 0, 2, 2)]
        let right = try #require(
            Boundaries.joinedResize("A", .right, frames: frames, grid: grid, minimumSize: noMinimum))
        #expect(right["A"]?.maxX == 870)
        #expect(right["B"]?.minX == 880)
        #expect(right["B"]?.maxX == 1130)

        let left = try #require(
            Boundaries.joinedResize("A", .left, frames: frames, grid: grid, minimumSize: noMinimum))
        #expect(left["A"]?.maxX == 350)
        #expect(left["B"]?.minX == 360)
    }

    @Test func windowAtRightEdgeUsesItsLeftBoundary() throws {
        // tmux rule: B has no right boundary inside the display, so h moves its left edge left (B grows).
        let frames = ["A": span(0, 0, 2, 2), "B": span(2, 0, 2, 2)]
        let result = try #require(
            Boundaries.joinedResize("B", .left, frames: frames, grid: grid, minimumSize: noMinimum))
        #expect(result["B"]?.minX == 360)
        #expect(result["A"]?.maxX == 350)
    }

    @Test func boundaryIncludesAllWindowsAcrossTheLine() throws {
        // A | (B / C)
        let frames = ["A": span(0, 0, 2, 2), "B": span(2, 0, 2, 1), "C": span(2, 1, 2, 1)]
        let result = try #require(
            Boundaries.joinedResize("A", .right, frames: frames, grid: grid, minimumSize: noMinimum))
        #expect(Set(result.keys) == ["A", "B", "C"])
        #expect(result["B"]?.minX == 880)
        #expect(result["C"]?.minX == 880)
        #expect(result["B"]?.minY == 50 && result["C"]?.minY == 310)
    }

    @Test func collinearSegmentsFormOneBoundary() throws {
        // 2x2 layout: moving the vertical line from the top-left window moves all four.
        let frames = [
            "TL": span(0, 0, 2, 1), "TR": span(2, 0, 2, 1),
            "BL": span(0, 1, 2, 1), "BR": span(2, 1, 2, 1),
        ]
        let result = try #require(
            Boundaries.joinedResize("TL", .left, frames: frames, grid: grid, minimumSize: noMinimum))
        #expect(result["TL"]?.maxX == 350 && result["BL"]?.maxX == 350)
        #expect(result["TR"]?.minX == 360 && result["BR"]?.minX == 360)
    }

    @Test func boundaryDoesNotReachTheDisplayEdge() {
        // With 2 rows the only interior horizontal line is the current one.
        let frames = [
            "TL": span(0, 0, 2, 1), "TR": span(2, 0, 2, 1),
            "BL": span(0, 1, 2, 1), "BR": span(2, 1, 2, 1),
        ]
        #expect(Boundaries.joinedResize("TL", .down, frames: frames, grid: grid, minimumSize: noMinimum) == nil)
        #expect(Boundaries.joinedResize("TL", .up, frames: frames, grid: grid, minimumSize: noMinimum) == nil)
    }

    @Test func loneEdgeMovesAloneAndMayReachTheDisplayEdge() throws {
        let frames = ["A": span(0, 0, 2, 2)]
        let once = try #require(
            Boundaries.joinedResize("A", .right, frames: frames, grid: grid, minimumSize: noMinimum))
        #expect(once["A"]?.maxX == 870)
        let twice = try #require(
            Boundaries.joinedResize("A", .right, frames: once, grid: grid, minimumSize: noMinimum))
        #expect(twice["A"]?.maxX == 1130)
    }

    @Test(arguments: [true, false])
    func fullWidthWindowShrinksFromTheFarEdge(joined: Bool) throws {
        let full = ["A": span(0, 0, 4, 2)]
        let left = try #require(
            Boundaries.joinedResize("A", .left, frames: full, grid: grid, minimumSize: noMinimum, joined: joined))
        #expect(left["A"] == span(0, 0, 3, 2))
        let right = try #require(
            Boundaries.joinedResize("A", .right, frames: full, grid: grid, minimumSize: noMinimum, joined: joined))
        #expect(right["A"] == span(1, 0, 3, 2))
        let up = try #require(
            Boundaries.joinedResize("A", .up, frames: full, grid: grid, minimumSize: noMinimum, joined: joined))
        #expect(up["A"] == span(0, 0, 4, 1))
        let down = try #require(
            Boundaries.joinedResize("A", .down, frames: full, grid: grid, minimumSize: noMinimum, joined: joined))
        #expect(down["A"] == span(0, 1, 4, 1))
    }

    @Test func fullWidthWindowStillMovesItsNeighboursVertically() throws {
        // Top full-width window over two bottom windows: j moves the horizontal line with both below.
        let taller = Grid(size: GridSize(columns: 4, rows: 4), area: grid.area, innerGap: 10)
        func cells(_ column: Int, _ row: Int, _ columns: Int, _ rows: Int) -> CGRect {
            taller.rect(for: CellSpan(column: column, row: row, columnCount: columns, rowCount: rows))
        }
        let frames = ["T": cells(0, 0, 4, 2), "L": cells(0, 2, 2, 2), "R": cells(2, 2, 2, 2)]
        let result = try #require(
            Boundaries.joinedResize("T", .down, frames: frames, grid: taller, minimumSize: noMinimum))
        #expect(result["T"] == cells(0, 0, 4, 3))
        #expect(result["L"] == cells(0, 3, 2, 1) && result["R"] == cells(2, 3, 2, 1))
    }

    @Test func distantWindowsAreNotJoined() throws {
        // B starts 50pt right of A: more than the gap, so A's edge moves alone.
        let frames = ["A": span(0, 0, 1, 2), "B": CGRect(x: 400, y: 50, width: 210, height: 510)]
        let result = try #require(
            Boundaries.joinedResize("A", .right, frames: frames, grid: grid, minimumSize: noMinimum))
        #expect(Set(result.keys) == ["A"])
        #expect(result["A"]?.maxX == 610)
    }

    @Test func slightlyOffGridNeighboursAreStillJoined() throws {
        // B was left 2pt short by an app that sizes in steps: gap 12 = innerGap + 2.
        let frames = ["A": span(0, 0, 2, 2), "B": CGRect(x: 622, y: 50, width: 508, height: 510)]
        let result = try #require(
            Boundaries.joinedResize("A", .right, frames: frames, grid: grid, minimumSize: noMinimum))
        #expect(result["B"]?.minX == 880)
    }

    @Test func neighboursBeyondTheGapToleranceAreNotJoined() throws {
        // Gap 14 > innerGap + 2.
        let frames = ["A": span(0, 0, 2, 2), "B": CGRect(x: 624, y: 50, width: 506, height: 510)]
        let result = try #require(
            Boundaries.joinedResize("A", .right, frames: frames, grid: grid, minimumSize: noMinimum))
        #expect(Set(result.keys) == ["A"])
    }

    @Test func refusesToGoBelowMinimumSize() {
        let frames = ["A": span(0, 0, 2, 2), "B": span(2, 0, 2, 2)]
        let minimum = CGSize(width: 400, height: 0)
        #expect(Boundaries.joinedResize("A", .right, frames: frames, grid: grid, minimumSize: minimum) == nil)
    }

    @Test func verticalBoundary() throws {
        // Top / bottom halves, bottom focused: its bottom edge is at the display edge, so k moves the top edge up.
        let frames = ["T": span(0, 0, 4, 1), "B": span(0, 1, 4, 1)]
        let taller = Grid(size: GridSize(columns: 4, rows: 4), area: grid.area, innerGap: 10)
        let result = try #require(
            Boundaries.joinedResize("B", .up, frames: frames, grid: taller, minimumSize: noMinimum))
        let line = taller.lines(.vertical)[1]
        #expect(result["T"]?.maxY == line - 5)
        #expect(result["B"]?.minY == line + 5)
        #expect(result["B"]?.maxY == 560)
    }

    // MARK: Separate resize

    @Test func aloneResizeUsesTheTmuxRuleButIgnoresNeighbours() throws {
        let frames = ["A": span(0, 0, 2, 2), "B": span(2, 0, 2, 2)]
        // A's right edge is inside the display: l grows A, h shrinks it. B is untouched.
        let grown = try #require(
            Boundaries.joinedResize("A", .right, frames: frames, grid: grid, minimumSize: noMinimum, joined: false))
        #expect(Set(grown.keys) == ["A"])
        #expect(grown["A"]?.maxX == 870)
        let shrunk = try #require(
            Boundaries.joinedResize("A", .left, frames: frames, grid: grid, minimumSize: noMinimum, joined: false))
        #expect(shrunk["A"]?.maxX == 350)

        // B touches the right side of the display: its left edge moves instead (h grows, l shrinks).
        let bGrown = try #require(
            Boundaries.joinedResize("B", .left, frames: frames, grid: grid, minimumSize: noMinimum, joined: false))
        #expect(Set(bGrown.keys) == ["B"])
        #expect(bGrown["B"]?.minX == 360 && bGrown["B"]?.maxX == 1130)
        let bShrunk = try #require(
            Boundaries.joinedResize("B", .right, frames: frames, grid: grid, minimumSize: noMinimum, joined: false))
        #expect(bShrunk["B"]?.minX == 880)
    }

    @Test func aloneResizeCanReachTheDisplayEdge() throws {
        let frames = ["A": span(0, 0, 3, 2), "B": span(3, 0, 1, 2)]
        let result = try #require(
            Boundaries.joinedResize("A", .right, frames: frames, grid: grid, minimumSize: noMinimum, joined: false))
        #expect(result["A"]?.maxX == 1130)
    }

    @Test func growAndShrinkEachEdge() {
        let frame = span(1, 0, 2, 1)  // x 360–870
        #expect(Boundaries.resizeEdge(frame, .left, grow: true, grid: grid, minimumSize: noMinimum)?.minX == 100)
        #expect(Boundaries.resizeEdge(frame, .right, grow: true, grid: grid, minimumSize: noMinimum)?.maxX == 1130)
        #expect(Boundaries.resizeEdge(frame, .left, grow: false, grid: grid, minimumSize: noMinimum)?.minX == 620)
        #expect(Boundaries.resizeEdge(frame, .right, grow: false, grid: grid, minimumSize: noMinimum)?.maxX == 610)
        #expect(Boundaries.resizeEdge(frame, .down, grow: true, grid: grid, minimumSize: noMinimum)?.maxY == 560)
        #expect(Boundaries.resizeEdge(frame, .up, grow: true, grid: grid, minimumSize: noMinimum) == nil)
    }

    @Test func resizeKeepsTheOppositeEdge() throws {
        let frame = span(1, 0, 2, 1)
        let grown = try #require(Boundaries.resizeEdge(frame, .left, grow: true, grid: grid, minimumSize: noMinimum))
        #expect(grown.maxX == frame.maxX && grown.minY == frame.minY && grown.maxY == frame.maxY)
    }

    @Test func shrinkingASingleCellIsRefused() {
        let cell = span(1, 0, 1, 1)
        #expect(Boundaries.resizeEdge(cell, .right, grow: false, grid: grid, minimumSize: noMinimum) == nil)
    }

    @Test func unalignedEdgeGoesToTheNextLine() {
        let frame = CGRect(x: 130, y: 60, width: 370, height: 200)
        #expect(Boundaries.resizeEdge(frame, .left, grow: true, grid: grid, minimumSize: noMinimum)?.minX == 100)
        #expect(Boundaries.resizeEdge(frame, .left, grow: false, grid: grid, minimumSize: noMinimum)?.minX == 360)
    }
}
