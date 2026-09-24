import CoreGraphics

/// A physical display, in AX (top-left origin, y down) coordinates.
public struct Display: Sendable, Equatable, Identifiable {
    /// Stable identifier (display UUID string); used to persist per-display state.
    public var id: String
    /// Full display bounds.
    public var frame: CGRect
    /// Bounds excluding the menu bar and Dock.
    public var visibleFrame: CGRect

    public init(id: String, frame: CGRect, visibleFrame: CGRect) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

extension Display {
    /// Displays in physical order: left to right, then top to bottom.
    public static func sortedPhysically(_ displays: [Display]) -> [Display] {
        displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    /// The display that shows the largest part of `rect`.
    /// Falls back to the display nearest to the rect's center when it is off-screen.
    public static func containing(_ rect: CGRect, in displays: [Display]) -> Display? {
        let best = displays.max { area($0.frame.intersection(rect)) < area($1.frame.intersection(rect)) }
        if let best, area(best.frame.intersection(rect)) > 0 {
            return best
        }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return displays.min { distance($0.frame, center) < distance($1.frame, center) }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
