import CoreGraphics

/// Lets edge and boundary logic be written once for both axes.
public enum Axis: Sendable, Hashable {
    /// Along x: vertical boundaries, left/right edges.
    case horizontal
    /// Along y: horizontal boundaries, top/bottom edges.
    case vertical

    public init(_ direction: Direction) {
        switch direction {
        case .left, .right: self = .horizontal
        case .up, .down: self = .vertical
        }
    }

    public var perpendicular: Axis {
        self == .horizontal ? .vertical : .horizontal
    }

    func lo(_ rect: CGRect) -> CGFloat { self == .horizontal ? rect.minX : rect.minY }
    func hi(_ rect: CGRect) -> CGFloat { self == .horizontal ? rect.maxX : rect.maxY }

    /// Returns `rect` with its low edge moved to `value`, keeping the high edge.
    func settingLo(_ rect: CGRect, _ value: CGFloat) -> CGRect {
        switch self {
        case .horizontal: CGRect(x: value, y: rect.minY, width: rect.maxX - value, height: rect.height)
        case .vertical: CGRect(x: rect.minX, y: value, width: rect.width, height: rect.maxY - value)
        }
    }

    /// Returns `rect` with its high edge moved to `value`, keeping the low edge.
    func settingHi(_ rect: CGRect, _ value: CGFloat) -> CGRect {
        switch self {
        case .horizontal: CGRect(x: rect.minX, y: rect.minY, width: value - rect.minX, height: rect.height)
        case .vertical: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: value - rect.minY)
        }
    }

    func length(_ size: CGSize) -> CGFloat { self == .horizontal ? size.width : size.height }
}

extension Direction {
    /// `true` for right and down (increasing coordinates in AX space).
    public var isForward: Bool { self == .right || self == .down }
}

extension Grid {
    /// Positions of the lines between cells along `axis`, measured at the
    /// middle of the inner gap. Index 0 and `count` are the outer edges
    /// (half a gap outside the area), so every cell edge is `line ∓ innerGap / 2`.
    func lines(_ axis: Axis) -> [CGFloat] {
        let count = axis == .horizontal ? size.columns : size.rows
        let stride = (axis == .horizontal ? cellWidth : cellHeight) + innerGap
        let start = axis.lo(area) - innerGap / 2
        return (0...count).map { start + CGFloat($0) * stride }
    }
}
