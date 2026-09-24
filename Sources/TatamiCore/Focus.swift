import CoreGraphics

/// Choosing which window to focus: by direction, or by hint label.
public enum FocusNavigation {
    /// The window to focus when moving from `focused` in `direction`.
    ///
    /// First the neighbour on the same display (same rule as swap). At the
    /// display's edge, the adjacent display's window nearest the entering
    /// edge, then nearest the focused window's center along that edge.
    public static func next<ID: Hashable>(
        from focused: ID, _ direction: Direction, windows: [ID: CGRect], displays: [Display]
    ) -> ID? {
        guard let frame = windows[focused], let display = Display.containing(frame, in: displays) else {
            return nil
        }
        let onDisplay = windows.filter { Display.containing($0.value, in: displays)?.id == display.id }
        if let neighbor = Swaps.neighbor(of: focused, direction, frames: onDisplay) {
            return neighbor
        }

        guard let next = Display.adjacent(to: display, direction, in: displays) else { return nil }
        let axis = Axis(direction)
        let along = axis.perpendicular
        let center = (along.lo(frame) + along.hi(frame)) / 2
        func key(_ rect: CGRect) -> (CGFloat, CGFloat) {
            let fromEdge =
                direction.isForward ? axis.lo(rect) - axis.lo(next.frame) : axis.hi(next.frame) - axis.hi(rect)
            return (fromEdge, abs((along.lo(rect) + along.hi(rect)) / 2 - center))
        }
        return windows.filter { Display.containing($0.value, in: displays)?.id == next.id }
            .min { key($0.value) < key($1.value) }?.key
    }
}

public enum FocusHintEffect<ID: Hashable>: Equatable {
    case updated
    case ignored
    case focus(ID)
}

/// The `⌃⌥ f` hint mode: a label on every window on every display; typing a
/// label focuses that window.
public struct FocusHintState<ID: Hashable> {
    /// Windows in label order: display by display (physical order), then
    /// reading order within each display.
    public let windows: [ID]
    public let frames: [ID: CGRect]
    public let labels: [String]
    /// Where each label is drawn: the window's center, nudged down so labels
    /// of stacked windows don't cover each other.
    public let positions: [CGPoint]
    public private(set) var typed = ""

    /// Label badges closer than this are moved apart.
    static var spacing: CGFloat { 44 }

    /// Returns `nil` when there are no windows.
    public init?(frames: [ID: CGRect], displays: [Display]) {
        guard !frames.isEmpty else { return nil }
        let ordered = Display.sortedPhysically(displays).map(\.id)
        func displayIndex(_ rect: CGRect) -> Int {
            Display.containing(rect, in: displays).flatMap { ordered.firstIndex(of: $0.id) } ?? ordered.count
        }
        windows = frames.keys.sorted { a, b in
            let fa = frames[a]!
            let fb = frames[b]!
            return (displayIndex(fa), fa.minY, fa.minX) < (displayIndex(fb), fb.minY, fb.minX)
        }
        self.frames = frames
        labels = GridLabels.sequence(count: frames.count)

        var placed: [CGPoint] = []
        for window in windows {
            let frame = frames[window]!
            var point = CGPoint(x: frame.midX, y: frame.midY)
            while placed.contains(where: { hypot($0.x - point.x, $0.y - point.y) < Self.spacing }) {
                point.y += Self.spacing
            }
            placed.append(point)
        }
        positions = placed
    }

    public mutating func type(_ character: Character) -> FocusHintEffect<ID> {
        let candidate = typed + String(character).lowercased()
        if let index = labels.firstIndex(of: candidate) {
            typed = ""
            return .focus(windows[index])
        }
        guard labels.contains(where: { $0.hasPrefix(candidate) }) else {
            typed = ""
            return .ignored
        }
        typed = candidate
        return .updated
    }
}
