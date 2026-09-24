import CoreGraphics
import Foundation

/// An auto-arrange layout: a pure function from a window count and an area to
/// frames. Frame 0 is the master (the focused window).
public enum Layout: String, Sendable, CaseIterable, Codable {
    case balancedGrid, masterStack, columns, rows, masterGrid, centeredMaster

    /// Share of the width the master takes in master + stack.
    static let masterRatio: CGFloat = 0.6
    /// Wider than 21:9 counts as ultrawide.
    static let ultrawideAspect: CGFloat = 21.0 / 9.0

    public var displayName: String {
        switch self {
        case .balancedGrid: "Balanced grid"
        case .masterStack: "Master + stack"
        case .columns: "Columns"
        case .rows: "Rows"
        case .masterGrid: "Master + grid"
        case .centeredMaster: "Centered master"
        }
    }

    /// Layouts offered for an area, in cycling order. Centered master only on ultrawide areas.
    public static func available(for area: CGRect) -> [Layout] {
        let ultrawide = area.width / max(area.height, 1) > ultrawideAspect
        return allCases.filter { $0 != .centeredMaster || ultrawide }
    }

    /// `count` frames tiling `area` with `gap` between neighbours.
    public func frames(count: Int, in area: CGRect, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [area] }
        switch self {
        case .balancedGrid:
            return Self.balancedGrid(count: count, in: area, gap: gap)
        case .columns:
            return Self.split(area, into: count, axis: .horizontal, gap: gap)
        case .rows:
            return Self.split(area, into: count, axis: .vertical, gap: gap)
        case .masterStack:
            let (master, rest) = Self.divide(area, ratio: Self.masterRatio, gap: gap)
            return [master] + Self.split(rest, into: count - 1, axis: .vertical, gap: gap)
        case .masterGrid:
            let (master, rest) = Self.divide(area, ratio: 0.5, gap: gap)
            return [master] + Self.balancedGrid(count: count - 1, in: rest, gap: gap)
        case .centeredMaster:
            return Self.centeredMaster(count: count, in: area, gap: gap)
        }
    }

    // MARK: - Building blocks

    /// Chooses the columns x rows whose cell shape is closest to the area's
    /// shape; windows in a partly filled last row widen to fill it.
    static func balancedGrid(count: Int, in area: CGRect, gap: CGFloat) -> [CGRect] {
        let areaAspect = area.width / max(area.height, 1)
        var best: (columns: Int, score: CGFloat)?
        for columns in 1...count {
            let rows = (count + columns - 1) / columns
            let cellWidth = (area.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let cellHeight = (area.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
            guard cellWidth > 0, cellHeight > 0 else { continue }
            let score = abs(log(cellWidth / cellHeight / areaAspect))
            // Ties (e.g. 2 windows) go to side-by-side on landscape areas.
            let better =
                best.map { score < $0.score - 0.0001 || (abs(score - $0.score) <= 0.0001 && areaAspect >= 1) }
                ?? true
            if better {
                best = (columns, score)
            }
        }
        let columns = best?.columns ?? 1
        let rows = (count + columns - 1) / columns
        let rowRects = split(area, into: rows, axis: .vertical, gap: gap)
        return rowRects.enumerated().flatMap { row, rect in
            let inRow = row == rows - 1 ? count - columns * (rows - 1) : columns
            return split(rect, into: inRow, axis: .horizontal, gap: gap)
        }
    }

    static func centeredMaster(count: Int, in area: CGRect, gap: CGFloat) -> [CGRect] {
        let side = (area.width - 2 * gap) / 4
        let others = count - 1
        let rightCount = (others + 1) / 2
        let leftCount = others / 2
        let right = CGRect(x: area.maxX - side, y: area.minY, width: side, height: area.height)
        let left = CGRect(x: area.minX, y: area.minY, width: side, height: area.height)
        let masterMinX = leftCount > 0 ? left.maxX + gap : area.minX
        let master = CGRect(x: masterMinX, y: area.minY, width: right.minX - gap - masterMinX, height: area.height)

        var rightFrames = split(right, into: rightCount, axis: .vertical, gap: gap)[...]
        var leftFrames = leftCount > 0 ? split(left, into: leftCount, axis: .vertical, gap: gap)[...] : []
        // Alternate right, left, right, ... so the stacks stay even.
        var frames = [master]
        for index in 0..<others {
            if index.isMultiple(of: 2), let next = rightFrames.popFirst() {
                frames.append(next)
            } else if let next = leftFrames.popFirst() {
                frames.append(next)
            }
        }
        return frames
    }

    /// Splits `area` into `count` equal parts along `axis`.
    static func split(_ area: CGRect, into count: Int, axis: Axis, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let length = axis == .horizontal ? area.width : area.height
        let part = (length - CGFloat(count - 1) * gap) / CGFloat(count)
        return (0..<count).map { index in
            let offset = CGFloat(index) * (part + gap)
            return axis == .horizontal
                ? CGRect(x: area.minX + offset, y: area.minY, width: part, height: area.height)
                : CGRect(x: area.minX, y: area.minY + offset, width: area.width, height: part)
        }
    }

    /// A left part taking `ratio` of the width (after the gap) and the rest.
    static func divide(_ area: CGRect, ratio: CGFloat, gap: CGFloat) -> (CGRect, CGRect) {
        let leftWidth = ((area.width - gap) * ratio).rounded()
        let left = CGRect(x: area.minX, y: area.minY, width: leftWidth, height: area.height)
        let right = CGRect(
            x: left.maxX + gap, y: area.minY, width: area.maxX - left.maxX - gap, height: area.height)
        return (left, right)
    }
}

/// Remembers the layout used per display and whether a repeated arrange
/// press continues a cycle.
public struct ArrangeHistory<ID: Hashable> {
    private var remembered: [String: Layout] = [:]
    private var last: (display: String, windows: Set<ID>, layout: Layout, time: Date)?

    public init() {}

    public func rememberedLayout(for display: String) -> Layout? {
        remembered[display]
    }

    /// The layout to use now. A press on the same display with the same
    /// windows within `timeout` of the last one steps through `available`
    /// (`step` +1 forward, -1 back); otherwise forward reuses the display's
    /// remembered layout and back steps back from it.
    public mutating func layout(
        display: String, windows: Set<ID>, available: [Layout], step: Int, now: Date, timeout: TimeInterval
    ) -> Layout {
        precondition(!available.isEmpty)
        let base: Layout
        let offset: Int
        if let last, last.display == display, last.windows == windows, now.timeIntervalSince(last.time) <= timeout {
            base = last.layout
            offset = step
        } else {
            base = remembered[display] ?? available[0]
            offset = step > 0 ? 0 : step
        }
        let index = available.firstIndex(of: base) ?? 0
        let count = available.count
        let layout = available[((index + offset) % count + count) % count]
        remembered[display] = layout
        last = (display, windows, layout, now)
        return layout
    }
}
