import CoreGraphics
import Foundation
import Testing

@testable import TatamiCore

/// 4x2 grid over a 1000x500 area at the origin with no gaps: cells are 250x250.
let plainGrid = Grid(
    size: GridSize(columns: 4, rows: 2), area: CGRect(x: 0, y: 0, width: 1000, height: 500), innerGap: 0)

/// 4x2 grid over 1030x510 with a 10pt gap: cells are 250x250 with 10pt between them.
let gappedGrid = Grid(
    size: GridSize(columns: 4, rows: 2), area: CGRect(x: 100, y: 50, width: 1030, height: 510), innerGap: 10)

struct GridSizeTests {
    @Test func clampsToLimits() {
        #expect(GridSize(columns: 0, rows: 99) == GridSize(columns: 1, rows: 24))
    }

    @Test func decodingClamps() throws {
        let size = try JSONDecoder().decode(GridSize.self, from: Data(#"{"columns": -3, "rows": 5}"#.utf8))
        #expect(size == GridSize(columns: 1, rows: 5))
    }
}

struct GridGeometryTests {
    @Test func cellSizeAccountsForGaps() {
        #expect(gappedGrid.cellWidth == 250)
        #expect(gappedGrid.cellHeight == 250)
    }

    @Test func rectForSpan() {
        let span = CellSpan(column: 1, row: 0, columnCount: 2, rowCount: 2)
        #expect(plainGrid.rect(for: span) == CGRect(x: 250, y: 0, width: 500, height: 500))
        #expect(gappedGrid.rect(for: span) == CGRect(x: 360, y: 50, width: 510, height: 510))
    }

    @Test func cellRectsTileTheGridRowByRow() {
        let cells = gappedGrid.cellRects()
        #expect(cells.count == 8)
        #expect(cells.first == CGRect(x: 100, y: 50, width: 250, height: 250))
        #expect(cells[4] == CGRect(x: 100, y: 310, width: 250, height: 250))
        #expect(cells.last?.maxX == gappedGrid.area.maxX)
    }

    @Test func fullSpanCoversArea() {
        #expect(gappedGrid.rect(for: gappedGrid.fullSpan) == gappedGrid.area)
    }

    @Test(arguments: [
        CellSpan(column: 0, row: 0, columnCount: 1, rowCount: 1),
        CellSpan(column: 3, row: 1, columnCount: 1, rowCount: 1),
        CellSpan(column: 1, row: 0, columnCount: 3, rowCount: 2),
        CellSpan(column: 0, row: 1, columnCount: 4, rowCount: 1),
    ])
    func snappingAnAlignedRectIsIdentity(span: CellSpan) {
        #expect(plainGrid.span(nearest: plainGrid.rect(for: span)) == span)
        #expect(gappedGrid.span(nearest: gappedGrid.rect(for: span)) == span)
    }

    @Test func snapsToNearestEdges() {
        // Left edge 130 is nearer 250 than 0; right edge 610 is nearer 500 than 750.
        let rect = CGRect(x: 130, y: 20, width: 480, height: 200)
        #expect(plainGrid.span(nearest: rect) == CellSpan(column: 1, row: 0, columnCount: 1, rowCount: 1))
    }

    @Test func snapNeverProducesAnEmptySpan() {
        let tiny = CGRect(x: 240, y: 240, width: 20, height: 20)
        let span = plainGrid.span(nearest: tiny)
        #expect(span.columnCount == 1 && span.rowCount == 1)
        #expect(plainGrid.contains(span))
    }

    @Test func snapClampsOffscreenRects() {
        let span = plainGrid.span(nearest: CGRect(x: -800, y: -300, width: 3000, height: 2000))
        #expect(span == plainGrid.fullSpan)
    }
}

struct GridCommandsTests {
    let span = CellSpan(column: 1, row: 0, columnCount: 2, rowCount: 1)

    @Test func moveInsideGrid() {
        #expect(
            GridCommands.move(span, .left, in: plainGrid) == CellSpan(column: 0, row: 0, columnCount: 2, rowCount: 1))
        #expect(
            GridCommands.move(span, .right, in: plainGrid) == CellSpan(column: 2, row: 0, columnCount: 2, rowCount: 1))
        #expect(
            GridCommands.move(span, .down, in: plainGrid) == CellSpan(column: 1, row: 1, columnCount: 2, rowCount: 1))
    }

    @Test func moveAtEdgeReturnsNil() {
        #expect(GridCommands.move(span, .up, in: plainGrid) == nil)
        let rightmost = CellSpan(column: 2, row: 0, columnCount: 2, rowCount: 1)
        #expect(GridCommands.move(rightmost, .right, in: plainGrid) == nil)
    }

    @Test func splitHalvesTheLongerSide() {
        // 3x2 span at the left of a 4x2 grid is 750x500: split columns, keep the half nearer the center.
        let wide = CellSpan(column: 0, row: 0, columnCount: 3, rowCount: 2)
        #expect(GridCommands.split(wide, in: plainGrid) == CellSpan(column: 1, row: 0, columnCount: 2, rowCount: 2))
    }

    @Test func splitFallsBackToTheOtherAxis() {
        // 1x2 span is 250x500 → split rows. Both halves are equally far from center → top half.
        let tall = CellSpan(column: 3, row: 0, columnCount: 1, rowCount: 2)
        #expect(GridCommands.split(tall, in: plainGrid) == CellSpan(column: 3, row: 0, columnCount: 1, rowCount: 1))
    }

    @Test func splitKeepsHalfNearerCenter() {
        let rightHalf = CellSpan(column: 2, row: 0, columnCount: 2, rowCount: 2)
        #expect(
            GridCommands.split(rightHalf, in: plainGrid) == CellSpan(column: 2, row: 0, columnCount: 1, rowCount: 2))
    }

    @Test func splitSingleCellIsNil() {
        #expect(GridCommands.split(CellSpan(column: 0, row: 0, columnCount: 1, rowCount: 1), in: plainGrid) == nil)
    }
}

struct GridStateTests {
    @Test func adjustClampsAndDefaults() {
        var state = GridState()
        #expect(state.size(for: "A", default: .default) == GridSize(columns: 4, rows: 2))
        #expect(state.adjust("A", columns: 1, default: .default) == GridSize(columns: 5, rows: 2))
        #expect(state.adjust("A", rows: -5, default: .default) == GridSize(columns: 5, rows: 1))
        #expect(state.size(for: "B", default: .default) == GridSize(columns: 4, rows: 2))
    }

    @Test func roundTripsThroughJSON() throws {
        let state = GridState(grids: ["A": GridSize(columns: 6, rows: 3)])
        let decoded = try JSONDecoder().decode(GridState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}
