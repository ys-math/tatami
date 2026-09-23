import CoreGraphics

public enum Direction: String, Sendable, CaseIterable {
    case left, down, up, right
}

/// Number of columns and rows of a display's grid.
public struct GridSize: Codable, Sendable, Hashable {
    public static let limits = 1...24
    public static let `default` = GridSize(columns: 4, rows: 2)

    public var columns: Int
    public var rows: Int

    /// Values are clamped to `limits`.
    public init(columns: Int, rows: Int) {
        self.columns = columns.clamped(to: Self.limits)
        self.rows = rows.clamped(to: Self.limits)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            columns: try container.decode(Int.self, forKey: .columns),
            rows: try container.decode(Int.self, forKey: .rows))
    }
}

public struct Gaps: Sendable, Equatable {
    /// Margin between the display's visible frame and the grid.
    public var outer: CGFloat
    /// Space between adjacent cells.
    public var inner: CGFloat

    public init(outer: CGFloat, inner: CGFloat) {
        self.outer = outer
        self.inner = inner
    }
}

/// A rectangle of whole grid cells. Row 0 is the top row.
public struct CellSpan: Sendable, Hashable, CustomStringConvertible {
    public var column: Int
    public var row: Int
    public var columnCount: Int
    public var rowCount: Int

    public init(column: Int, row: Int, columnCount: Int, rowCount: Int) {
        self.column = column
        self.row = row
        self.columnCount = columnCount
        self.rowCount = rowCount
    }

    public var description: String {
        "(\(column),\(row) \(columnCount)x\(rowCount))"
    }
}

/// A grid laid over an area of the screen, converting between cell spans and frames.
public struct Grid: Sendable, Equatable {
    public var size: GridSize
    /// The region the grid covers: the display's visible frame inset by the outer gap.
    public var area: CGRect
    public var innerGap: CGFloat

    public init(size: GridSize, area: CGRect, innerGap: CGFloat) {
        self.size = size
        self.area = area
        self.innerGap = innerGap
    }

    public init(size: GridSize, display: Display, gaps: Gaps) {
        self.init(
            size: size, area: display.visibleFrame.insetBy(dx: gaps.outer, dy: gaps.outer), innerGap: gaps.inner)
    }

    public var cellWidth: CGFloat {
        (area.width - CGFloat(size.columns - 1) * innerGap) / CGFloat(size.columns)
    }

    public var cellHeight: CGFloat {
        (area.height - CGFloat(size.rows - 1) * innerGap) / CGFloat(size.rows)
    }

    public var fullSpan: CellSpan {
        CellSpan(column: 0, row: 0, columnCount: size.columns, rowCount: size.rows)
    }

    /// Frames of every single cell, row by row from the top-left.
    public func cellRects() -> [CGRect] {
        (0..<size.rows).flatMap { row in
            (0..<size.columns).map { column in
                rect(for: CellSpan(column: column, row: row, columnCount: 1, rowCount: 1))
            }
        }
    }

    public func contains(_ span: CellSpan) -> Bool {
        span.column >= 0 && span.row >= 0 && span.columnCount >= 1 && span.rowCount >= 1
            && span.column + span.columnCount <= size.columns && span.row + span.rowCount <= size.rows
    }

    public func rect(for span: CellSpan) -> CGRect {
        let strideX = cellWidth + innerGap
        let strideY = cellHeight + innerGap
        return CGRect(
            x: area.minX + CGFloat(span.column) * strideX,
            y: area.minY + CGFloat(span.row) * strideY,
            width: CGFloat(span.columnCount) * strideX - innerGap,
            height: CGFloat(span.rowCount) * strideY - innerGap)
    }

    /// The cell span whose edges are nearest to the edges of `rect`.
    public func span(nearest rect: CGRect) -> CellSpan {
        let (column, columnCount) = Self.snap(
            rect.minX, rect.maxX, origin: area.minX, stride: cellWidth + innerGap, gap: innerGap, count: size.columns)
        let (row, rowCount) = Self.snap(
            rect.minY, rect.maxY, origin: area.minY, stride: cellHeight + innerGap, gap: innerGap, count: size.rows)
        return CellSpan(column: column, row: row, columnCount: columnCount, rowCount: rowCount)
    }

    /// Snaps one axis: cell edges sit at `origin + i * stride` (start) and
    /// `origin + i * stride - gap` (end).
    private static func snap(
        _ minValue: CGFloat, _ maxValue: CGFloat, origin: CGFloat, stride: CGFloat, gap: CGFloat, count: Int
    ) -> (start: Int, length: Int) {
        let start = Int(((minValue - origin) / stride).rounded()).clamped(to: 0...(count - 1))
        let end = Int(((maxValue - origin + gap) / stride).rounded()).clamped(to: (start + 1)...count)
        return (start, end - start)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
