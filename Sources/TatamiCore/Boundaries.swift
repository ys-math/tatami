import CoreGraphics

/// A straight line where windows meet: every window in `before` has its high
/// edge on the line, every window in `after` its low edge.
public struct Boundary<ID: Hashable>: Equatable {
    public var axis: Axis
    /// Position at the middle of the gap between the two sides.
    public var position: CGFloat
    public var before: Set<ID>
    public var after: Set<ID>
    /// The span of the line along the boundary (y range for a vertical line).
    public var extent: ClosedRange<CGFloat>

    /// `true` when windows sit on both sides of the line.
    public var isJoined: Bool { !before.isEmpty && !after.isEmpty }
    public var members: Set<ID> { before.union(after) }

    /// The middle of the line, in AX coordinates.
    public var midpoint: CGPoint {
        let along = (extent.lowerBound + extent.upperBound) / 2
        return axis == .horizontal ? CGPoint(x: position, y: along) : CGPoint(x: along, y: position)
    }
}

extension Boundary {
    /// One boundary moving all of `parts` together (they share an axis).
    static func merged(_ parts: [Boundary]) -> Boundary {
        precondition(!parts.isEmpty)
        let position = parts.map(\.position).reduce(0, +) / CGFloat(parts.count)
        let low = parts.map(\.extent.lowerBound).min()!
        let high = parts.map(\.extent.upperBound).max()!
        return Boundary(
            axis: parts[0].axis, position: position,
            before: parts.reduce(into: Set()) { $0.formUnion($1.before) },
            after: parts.reduce(into: Set()) { $0.formUnion($1.after) }, extent: low...high)
    }
}

/// A point where vertical and horizontal boundaries meet (a T or + junction).
/// Moving it moves every boundary touching it along the chosen axis.
public struct Crosspoint<ID: Hashable>: Equatable {
    /// Vertical lines (`axis == .horizontal`) ending at or passing through the point.
    public var verticals: [Boundary<ID>]
    /// Horizontal lines (`axis == .vertical`) ending at or passing through the point.
    public var horizontals: [Boundary<ID>]
    public var point: CGPoint

    /// What moves for a horizontal move (`h`/`l`).
    public var vertical: Boundary<ID> { .merged(verticals) }
    /// What moves for a vertical move (`j`/`k`).
    public var horizontal: Boundary<ID> { .merged(horizontals) }
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
    ///
    /// With `minimal`, windows are added only when their edge faces a window
    /// already on the other side, giving the smallest group that can move
    /// without moving part of a window's edge (the top half of a 2x2's middle
    /// line on its own, but all of `A | (B / C)`).
    public static func boundary<ID: Hashable>(
        of focused: ID, highEdge: Bool, axis: Axis, frames: [ID: CGRect], innerGap: CGFloat, minimal: Bool = false
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
                let onBefore = abs(axis.hi(rect) - position) <= tolerance
                let onAfter = !onBefore && abs(axis.lo(rect) - position) <= tolerance
                guard onBefore || onAfter else { continue }
                if minimal {
                    let facing = onBefore ? after : before
                    let faces = facing.contains { other in
                        frames[other].map { overlap(rect, $0, along: along) > slack } ?? false
                    }
                    guard faces else { continue }
                } else {
                    let touches =
                        along.lo(rect) <= extent.upperBound + innerGap + slack
                        && along.hi(rect) >= extent.lowerBound - innerGap - slack
                    guard touches else { continue }
                }
                if onBefore {
                    before.insert(id)
                } else {
                    after.insert(id)
                }
                extent = min(extent.lowerBound, along.lo(rect))...max(extent.upperBound, along.hi(rect))
                changed = true
            }
        }

        if before.isEmpty || after.isEmpty {
            return Boundary(
                axis: axis, position: position, before: highEdge ? [focused] : [],
                after: highEdge ? [] : [focused], extent: along.lo(frame)...along.hi(frame))
        }
        return Boundary(axis: axis, position: position, before: before, after: after, extent: extent)
    }

    /// Every minimal joined boundary on the display (see `boundary(…minimal:)`),
    /// and every point where vertical and horizontal ones meet. Sorted
    /// top-to-bottom, left-to-right.
    public static func all<ID: Hashable>(
        frames: [ID: CGRect], grid: Grid
    ) -> (boundaries: [Boundary<ID>], crosspoints: [Crosspoint<ID>]) {
        let tolerance = grid.innerGap / 2 + slack
        var boundaries: [Boundary<ID>] = []
        for axis in [Axis.horizontal, .vertical] {
            for (id, frame) in frames where axis.hi(frame) < axis.hi(grid.area) - tolerance {
                guard
                    let boundary = boundary(
                        of: id, highEdge: true, axis: axis, frames: frames, innerGap: grid.innerGap, minimal: true),
                    boundary.isJoined,
                    !boundaries.contains(where: { $0.axis == axis && $0.members == boundary.members })
                else { continue }
                boundaries.append(boundary)
            }
        }
        boundaries.sort { ($0.midpoint.y, $0.midpoint.x) < ($1.midpoint.y, $1.midpoint.x) }

        // Pair every vertical with every horizontal it meets, then merge pairs at the same point.
        let reach = grid.innerGap + slack
        var crosspoints: [Crosspoint<ID>] = []
        for vertical in boundaries where vertical.axis == .horizontal {
            for horizontal in boundaries where horizontal.axis == .vertical {
                let meets =
                    vertical.extent.lowerBound - reach <= horizontal.position
                    && horizontal.position <= vertical.extent.upperBound + reach
                    && horizontal.extent.lowerBound - reach <= vertical.position
                    && vertical.position <= horizontal.extent.upperBound + reach
                guard meets else { continue }
                let point = CGPoint(x: vertical.position, y: horizontal.position)
                if let index = crosspoints.firstIndex(where: {
                    abs($0.point.x - point.x) <= reach && abs($0.point.y - point.y) <= reach
                }) {
                    if !crosspoints[index].verticals.contains(vertical) {
                        crosspoints[index].verticals.append(vertical)
                    }
                    if !crosspoints[index].horizontals.contains(horizontal) {
                        crosspoints[index].horizontals.append(horizontal)
                    }
                } else {
                    crosspoints.append(Crosspoint(verticals: [vertical], horizontals: [horizontal], point: point))
                }
            }
        }
        crosspoints.sort { ($0.point.y, $0.point.x) < ($1.point.y, $1.point.x) }
        return (boundaries, crosspoints)
    }

    /// Where to put a boundary's label: the middle of its longest stretch
    /// between the points in `junctions`, so it never sits on a crosspoint.
    public static func labelPoint<ID: Hashable>(for boundary: Boundary<ID>, junctions: [CGPoint]) -> CGPoint {
        let along = boundary.axis.perpendicular
        let cuts = junctions.map { along == .horizontal ? $0.x : $0.y }
            .filter { $0 > boundary.extent.lowerBound && $0 < boundary.extent.upperBound }
        let stops = [boundary.extent.lowerBound] + cuts.sorted() + [boundary.extent.upperBound]
        let longest = zip(stops, stops.dropFirst()).max { $0.1 - $0.0 < $1.1 - $1.0 }!
        let middle = (longest.0 + longest.1) / 2
        return boundary.axis == .horizontal
            ? CGPoint(x: boundary.position, y: middle) : CGPoint(x: middle, y: boundary.position)
    }

    /// Length of the shared stretch of `a` and `b` along `axis`.
    static func overlap(_ a: CGRect, _ b: CGRect, along axis: Axis) -> CGFloat {
        min(axis.hi(a), axis.hi(b)) - max(axis.lo(a), axis.lo(b))
    }

    /// The next grid line from `boundary` in `direction`, or `nil` at the end.
    /// A joined boundary stays inside the display; a lone edge may reach its border.
    public static func nextGridLine<ID: Hashable>(
        for boundary: Boundary<ID>, forward: Bool, grid: Grid
    ) -> CGFloat? {
        var lines = grid.lines(boundary.axis)
        if boundary.isJoined {
            lines = Array(lines.dropFirst().dropLast())
        }
        return nextLine(after: boundary.position, forward: forward, in: lines)
    }

    /// Moves `boundary` to the next grid line in `direction` (forward = right/down).
    /// Returns the new frames of the affected windows, or `nil` if there is no
    /// further line or a window would become smaller than `minimumSize`.
    public static func move<ID: Hashable>(
        _ boundary: Boundary<ID>, forward: Bool, frames: [ID: CGRect], grid: Grid, minimumSize: CGSize
    ) -> [ID: CGRect]? {
        guard let target = nextGridLine(for: boundary, forward: forward, grid: grid) else { return nil }
        return move(boundary, to: target, frames: frames, innerGap: grid.innerGap, minimumSize: minimumSize)
    }

    /// Moves `boundary` so the middle of its gap sits at `target`.
    /// Returns `nil` if a window would become smaller than `minimumSize`.
    public static func move<ID: Hashable>(
        _ boundary: Boundary<ID>, to target: CGFloat, frames: [ID: CGRect], innerGap: CGFloat, minimumSize: CGSize
    ) -> [ID: CGRect]? {
        let axis = boundary.axis
        let half = innerGap / 2
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
    /// grid, otherwise its left (top) one; a window spanning the whole axis
    /// shrinks from the edge opposite `direction`. When `joined`, every window on the
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
            // Spans the whole axis: shrink by moving the far edge in `direction`
            // (h pulls the right edge left, l pulls the left edge right).
            highEdge = !direction.isForward
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
        let along = axis.perpendicular
        let boundary = Boundary<Int>(
            axis: axis,
            position: highEdge ? axis.hi(frame) + grid.innerGap / 2 : axis.lo(frame) - grid.innerGap / 2,
            before: highEdge ? [0] : [], after: highEdge ? [] : [0], extent: along.lo(frame)...along.hi(frame))
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
