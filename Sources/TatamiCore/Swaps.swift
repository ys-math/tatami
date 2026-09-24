import CoreGraphics
import Foundation

/// Moving windows between existing slots: frames are exchanged, never resized
/// to anything new, so the layout stays as it is.
public enum Swaps {
    /// The window next to `focused` in `direction`: its center lies beyond
    /// that edge and it shares part of the edge. Nearest first, then the
    /// longest shared stretch.
    public static func neighbor<ID: Hashable>(of focused: ID, _ direction: Direction, frames: [ID: CGRect]) -> ID? {
        guard let frame = frames[focused] else { return nil }
        let axis = Axis(direction)
        let along = axis.perpendicular
        func center(_ rect: CGRect) -> CGFloat { (axis.lo(rect) + axis.hi(rect)) / 2 }
        func gap(_ rect: CGRect) -> CGFloat {
            direction.isForward ? axis.lo(rect) - axis.hi(frame) : axis.lo(frame) - axis.hi(rect)
        }
        let candidates = frames.filter { id, rect in
            id != focused
                && (direction.isForward ? center(rect) > axis.hi(frame) : center(rect) < axis.lo(frame))
                && Boundaries.overlap(frame, rect, along: along) > 0
        }
        return candidates.min { a, b in
            (max(gap(a.value), 0), -Boundaries.overlap(frame, a.value, along: along))
                < (max(gap(b.value), 0), -Boundaries.overlap(frame, b.value, along: along))
        }?.key
    }

    /// New frames after `a` and `b` trade places.
    public static func swap<ID: Hashable>(_ a: ID, _ b: ID, frames: [ID: CGRect]) -> [ID: CGRect]? {
        guard a != b, let frameA = frames[a], let frameB = frames[b] else { return nil }
        return [a: frameB, b: frameA]
    }

    /// Every window moves one slot clockwise (or counter-clockwise) around
    /// the center of all the windows. Returns `nil` for fewer than two windows.
    public static func rotate<ID: Hashable>(_ frames: [ID: CGRect], clockwise: Bool) -> [ID: CGRect]? {
        guard frames.count > 1 else { return nil }
        let ordered = clockwiseOrder(frames)
        var result: [ID: CGRect] = [:]
        for (index, id) in ordered.enumerated() {
            let step = clockwise ? 1 : ordered.count - 1
            result[id] = frames[ordered[(index + step) % ordered.count]]
        }
        return result
    }

    /// Windows sorted clockwise on screen around the centroid of their
    /// centers, starting from the left (AX y points down, so increasing
    /// `atan2` is clockwise).
    static func clockwiseOrder<ID: Hashable>(_ frames: [ID: CGRect]) -> [ID] {
        let centers = frames.mapValues { CGPoint(x: $0.midX, y: $0.midY) }
        let cx = centers.values.map(\.x).reduce(0, +) / CGFloat(centers.count)
        let cy = centers.values.map(\.y).reduce(0, +) / CGFloat(centers.count)
        func key(_ id: ID) -> (CGFloat, CGFloat) {
            let point = centers[id]!
            // Shift so the order starts at the left (angle pi) and increases clockwise.
            var angle = atan2(point.y - cy, point.x - cx) - .pi
            if angle < -1e-9 { angle += 2 * .pi }
            return (angle, hypot(point.x - cx, point.y - cy))
        }
        return frames.keys.sorted { key($0) < key($1) }
    }

    /// The main window: the largest one (earlier in `order` on ties). If
    /// `focused` is already it, the next largest, so the pair always swaps.
    public static func mainPartner<ID: Hashable>(of focused: ID, frames: [ID: CGRect], order: [ID]) -> ID? {
        let ranked = order.filter { frames[$0] != nil }.enumerated().sorted { a, b in
            let areaA = frames[a.element]!.width * frames[a.element]!.height
            let areaB = frames[b.element]!.width * frames[b.element]!.height
            return areaA != areaB ? areaA > areaB : a.offset < b.offset
        }.map(\.element)
        guard let main = ranked.first else { return nil }
        return main == focused ? ranked.dropFirst().first : main
    }
}
