import CoreGraphics

/// A straight line where windows meet: every window in `before` has its high
/// edge on the line, every window in `after` its low edge.
public struct Boundary<ID: Hashable>: Equatable {
    public var axis: Axis
    /// Position at the middle of the gap between the two sides.
    public var position: CGFloat
    public var before: Set<ID>
    public var after: Set<ID>
}

/// Boundary detection and edge moves. All frames are in AX coordinates and
/// belong to a single display.
public enum Boundaries {
    /// Edges closer than this to a line count as being on it; also the extra
    /// slack allowed on top of the inner gap between joined windows.
    static let slack: CGFloat = 2

    /// The maximal boundary through one edge of `focused`.
    ///
    /// Starting from the focused window, windows are added while their edge
    /// lies on the line and their extent along the line touches the boundary
    /// found so far, so collinear runs (like the full middle line of a 2x2
    /// layout) move together. If nothing is on the other side, the boundary
    /// holds only the focused window.
    public static func boundary<ID: Hashable>(
        of focused: ID, highEdge: Bool, axis: Axis, frames: [ID: CGRect], innerGap: CGFloat
    ) -> Boundary<ID>? {
        guard let frame = frames[focused] else { return nil }
        let half = innerGap / 2
        let position = highEdge ? axis.hi(frame) + half : axis.lo(frame) - half
        let tolerance = half + slack
        let along = axis.perpendicular

        var before: Set<ID> = highEdge ? [focused] : []
        var after: Set<ID> = highEdge ? [] : [focused]
        var extent = along.lo(frame)...along.hi(frame)

        var changed = true
        while changed {
            changed = false
            for (id, rect) in frames where !before.contains(id) && !after.contains(id) {
                let touches =
                    along.lo(rect) <= extent.upperBound + innerGap + slack
                    && along.hi(rect) >= extent.lowerBound - innerGap - slack
                guard touches else { continue }
                if abs(axis.hi(rect) - position) <= tolerance {
                    before.insert(id)
                } else if abs(axis.lo(rect) - position) <= tolerance {
                    after.insert(id)
                } else {
                    continue
                }
                extent = min(extent.lowerBound, along.lo(rect))...max(extent.upperBound, along.hi(rect))
                changed = true
            }
        }

        if before.isEmpty || after.isEmpty {
            return Boundary(
                axis: axis, position: position, before: highEdge ? [focused] : [],
                after: highEdge ? [] : [focused])
        }
        return Boundary(axis: axis, position: position, before: before, after: after)
    }

    /// Moves `boundary` to the next grid line in `direction` (forward = right/down).
    /// Returns the new frames of the affected windows, or `nil` if there is no
    /// further line or a window would become smaller than `minimumSize`.
    public static func move<ID: Hashable>(
        _ boundary: Boundary<ID>, forward: Bool, frames: [ID: CGRect], grid: Grid, minimumSize: CGSize
    ) -> [ID: CGRect]? {
        var lines = grid.lines(boundary.axis)
        // A real boundary stays inside the display; a lone edge may reach its border.
        if !boundary.before.isEmpty && !boundary.after.isEmpty {
            lines = Array(lines.dropFirst().dropLast())
        }
        guard let target = nextLine(after: boundary.position, forward: forward, in: lines) else { return nil }

        let axis = boundary.axis
        let half = grid.innerGap / 2
        let minimum = axis.length(minimumSize)
        var result: [ID: CGRect] = [:]
        for id in boundary.before {
            guard let frame = frames[id] else { continue }
            let edge = target - half
            // Checked on edge positions: CGRect would silently normalize a negative size.
            guard edge - axis.lo(frame) >= max(minimum, 1) else { return nil }
            result[id] = axis.settingHi(frame, edge)
        }
        for id in boundary.after {
            guard let frame = frames[id] else { continue }
            let edge = target + half
            guard axis.hi(frame) - edge >= max(minimum, 1) else { return nil }
            result[id] = axis.settingLo(frame, edge)
        }
        return result
    }

    /// Resize with the tmux-style rule: `direction` is where the edge moves.
    /// Uses the focused window's right (bottom) edge if it lies inside the
    /// grid, otherwise its left (top) one. When `joined`, every window on the
    /// boundary through that edge moves with it; otherwise only the focused
    /// window's edge moves.
    public static func joinedResize<ID: Hashable>(
        _ focused: ID, _ direction: Direction, frames: [ID: CGRect], grid: Grid, minimumSize: CGSize,
        joined: Bool = true
    ) -> [ID: CGRect]? {
        guard let frame = frames[focused] else { return nil }
        let axis = Axis(direction)
        let tolerance = grid.innerGap / 2 + slack
        let highEdge: Bool
        if axis.hi(frame) < axis.hi(grid.area) - tolerance {
            highEdge = true
        } else if axis.lo(frame) > axis.lo(grid.area) + tolerance {
            highEdge = false
        } else {
            return nil  // Spans the whole axis: no boundary to move.
        }
        guard
            let boundary = boundary(
                of: focused, highEdge: highEdge, axis: axis, frames: joined ? frames : [focused: frame],
                innerGap: grid.innerGap)
        else { return nil }
        return move(boundary, forward: direction.isForward, frames: frames, grid: grid, minimumSize: minimumSize)
    }

    /// Separate resize: moves only the named edge of `frame` one grid line
    /// outward (`grow`) or inward, ignoring other windows.
    public static func resizeEdge(
        _ frame: CGRect, _ edge: Direction, grow: Bool, grid: Grid, minimumSize: CGSize
    ) -> CGRect? {
        let axis = Axis(edge)
        let highEdge = edge.isForward
        let boundary = Boundary<Int>(
            axis: axis,
            position: highEdge ? axis.hi(frame) + grid.innerGap / 2 : axis.lo(frame) - grid.innerGap / 2,
            before: highEdge ? [0] : [], after: highEdge ? [] : [0])
        // Growing moves a high edge forward and a low edge backward.
        let forward = grow == highEdge
        return move(boundary, forward: forward, frames: [0: frame], grid: grid, minimumSize: minimumSize)?[0]
    }

    private static func nextLine(after position: CGFloat, forward: Bool, in lines: [CGFloat]) -> CGFloat? {
        forward
            ? lines.first { $0 > position + slack / 2 }
            : lines.last { $0 < position - slack / 2 }
    }
}
