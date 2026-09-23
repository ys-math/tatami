/// Operations on cell spans within a grid.
public enum GridCommands {
    /// Shifts the span one cell in `direction`.
    /// Returns `nil` when the span already touches that edge of the grid.
    public static func move(_ span: CellSpan, _ direction: Direction, in grid: Grid) -> CellSpan? {
        var moved = span
        switch direction {
        case .left: moved.column -= 1
        case .right: moved.column += 1
        case .up: moved.row -= 1
        case .down: moved.row += 1
        }
        return grid.contains(moved) ? moved : nil
    }

    /// Halves the span along its longer side (in points), keeping the half
    /// nearer the grid's center. Falls back to the other axis when the longer
    /// side is a single cell. Returns `nil` for a 1x1 span.
    public static func split(_ span: CellSpan, in grid: Grid) -> CellSpan? {
        let splitColumns: Bool
        switch (span.columnCount > 1, span.rowCount > 1) {
        case (false, false): return nil
        case (true, false): splitColumns = true
        case (false, true): splitColumns = false
        case (true, true):
            let rect = grid.rect(for: span)
            splitColumns = rect.width >= rect.height
        }

        var first = span
        var second = span
        if splitColumns {
            first.columnCount = span.columnCount / 2
            second.column = span.column + first.columnCount
            second.columnCount = span.columnCount - first.columnCount
        } else {
            first.rowCount = span.rowCount / 2
            second.row = span.row + first.rowCount
            second.rowCount = span.rowCount - first.rowCount
        }
        let center = grid.area
        func distance(_ candidate: CellSpan) -> Double {
            let r = grid.rect(for: candidate)
            return Double(splitColumns ? abs(r.midX - center.midX) : abs(r.midY - center.midY))
        }
        return distance(second) < distance(first) ? second : first
    }
}
