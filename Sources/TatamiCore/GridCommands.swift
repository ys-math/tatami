/// Operations on cell spans within a grid.
public enum GridCommands {
    /// Shifts the span one cell in `direction`.
    /// Returns `nil` when the span already touches that edge of the grid.
    public static func move(_ span: CellSpan, _ direction: Direction, in grid: Grid) -> CellSpan? {
        move(span, direction, in: grid.size)
    }

    public static func move(_ span: CellSpan, _ direction: Direction, in size: GridSize) -> CellSpan? {
        var moved = span
        switch direction {
        case .left: moved.column -= 1
        case .right: moved.column += 1
        case .up: moved.row -= 1
        case .down: moved.row += 1
        }
        return size.contains(moved) ? moved : nil
    }

    /// Tmux-style resize of a span by one cell: `direction` is where the edge
    /// moves. Uses the high (right/bottom) edge if it is inside the grid,
    /// otherwise the low edge; a span covering the whole axis shrinks from the
    /// edge opposite `direction`. Returns `nil` if the span would vanish.
    public static func resize(_ span: CellSpan, _ direction: Direction, in size: GridSize) -> CellSpan? {
        let axis = Axis(direction)
        let count = size.count(axis)
        let low = span.start(axis)
        let high = low + span.length(axis)
        let step = direction.isForward ? 1 : -1

        var newLow = low
        var newHigh = high
        if high < count {
            newHigh += step
        } else if low > 0 {
            newLow += step
        } else if direction.isForward {
            newLow += 1
        } else {
            newHigh -= 1
        }
        guard newLow >= 0, newHigh <= count, newHigh > newLow else { return nil }
        return span.setting(axis, start: newLow, length: newHigh - newLow)
    }

    /// Where a span lands after crossing a display edge in `direction`: at
    /// the entering edge of the new grid, keeping its size in cells (clamped),
    /// with the other axis mapped proportionally.
    public static func cross(
        _ span: CellSpan, _ direction: Direction, from old: GridSize, to new: GridSize
    ) -> CellSpan {
        let axis = Axis(direction)
        let count = new.count(axis)
        let length = min(span.length(axis), count)
        let mapped = map(span, from: old, to: new)
        return mapped.setting(axis, start: direction.isForward ? 0 : count - length, length: length)
    }

    /// Maps a span proportionally onto a grid of another size (the left half
    /// stays the left half). Never returns an empty span.
    public static func map(_ span: CellSpan, from old: GridSize, to new: GridSize) -> CellSpan {
        var result = span
        for axis in [Axis.horizontal, .vertical] {
            let oldCount = Double(old.count(axis))
            let newCount = new.count(axis)
            let scale = Double(newCount) / oldCount
            let low = Int((Double(span.start(axis)) * scale).rounded()).clamped(to: 0...(newCount - 1))
            let high = Int((Double(span.start(axis) + span.length(axis)) * scale).rounded())
                .clamped(to: (low + 1)...newCount)
            result = result.setting(axis, start: low, length: high - low)
        }
        return result
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
