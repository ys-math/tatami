import CoreGraphics

/// Something boundary mode can select and move.
public enum BoundaryItem<ID: Hashable>: Equatable {
    case boundary(Boundary<ID>)
    case crosspoint(Crosspoint<ID>)

    /// Where the item is drawn and labelled.
    public var anchor: CGPoint {
        switch self {
        case .boundary(let boundary): boundary.midpoint
        case .crosspoint(let crosspoint): crosspoint.point
        }
    }

    public var isCrosspoint: Bool {
        if case .crosspoint = self { true } else { false }
    }

    /// The line that moves for a move along `axis`, if the item can move that way.
    func line(movingAlong axis: Axis) -> Boundary<ID>? {
        switch self {
        case .boundary(let boundary):
            boundary.axis == axis ? boundary : nil
        case .crosspoint(let crosspoint):
            axis == .horizontal ? crosspoint.vertical : crosspoint.horizontal
        }
    }

    var kind: Int {
        switch self {
        case .boundary(let boundary): boundary.axis == .horizontal ? 0 : 1
        case .crosspoint: 2
        }
    }
}

public enum BoundaryModeInput: Equatable, Sendable {
    /// `hjkl`: move the selection to the next grid line.
    case move(Direction)
    /// `HJKL`: move the selection by the fine step.
    case fineMove(Direction)
    case character(Character)
    /// Tab / Shift-Tab.
    case next, previous
    /// Return or Escape; moves are applied live, so both just leave.
    case exit
}

public enum BoundaryModeEffect<ID: Hashable>: Equatable {
    case updated
    case ignored
    /// Set these frames. The state already assumes they were applied; call
    /// `refresh(frames:)` with the real frames afterwards.
    case apply([ID: CGRect])
    case exit
}

/// The state of boundary mode: the joined boundaries and crosspoints on one
/// display, the selected one, and label typing. Pure; the app applies the
/// frames it returns.
public struct BoundaryModeState<ID: Hashable> {
    public private(set) var frames: [ID: CGRect]
    public private(set) var items: [BoundaryItem<ID>] = []
    public private(set) var selectedIndex = 0
    public private(set) var typed = ""
    public let grid: Grid
    public let minimumSize: CGSize
    public let fineStep: CGFloat

    /// Returns `nil` when the display has no joined boundaries.
    public init?(frames: [ID: CGRect], focused: ID?, grid: Grid, minimumSize: CGSize, fineStep: CGFloat) {
        self.frames = frames
        self.grid = grid
        self.minimumSize = minimumSize
        self.fineStep = fineStep
        enumerate()
        guard !items.isEmpty else { return nil }
        selectedIndex = initialSelection(focused: focused)
    }

    public var labels: [String] { GridLabels.sequence(count: items.count) }
    public var selected: BoundaryItem<ID> { items[selectedIndex] }

    public mutating func handle(_ input: BoundaryModeInput) -> BoundaryModeEffect<ID> {
        switch input {
        case .move(let direction):
            typed = ""
            guard let line = selected.line(movingAlong: Axis(direction)),
                let target = Boundaries.nextGridLine(for: line, forward: direction.isForward, grid: grid)
            else { return .ignored }
            return move(line, to: target)
        case .fineMove(let direction):
            typed = ""
            guard let line = selected.line(movingAlong: Axis(direction)) else { return .ignored }
            return move(line, to: line.position + (direction.isForward ? fineStep : -fineStep))
        case .character(let character):
            return type(character)
        case .next:
            typed = ""
            selectedIndex = (selectedIndex + 1) % items.count
            return .updated
        case .previous:
            typed = ""
            selectedIndex = (selectedIndex + items.count - 1) % items.count
            return .updated
        case .exit:
            return .exit
        }
    }

    /// Replaces the frames with what the windows actually did and re-finds
    /// the boundaries, keeping the nearest item of the same kind selected.
    public mutating func refresh(frames: [ID: CGRect]) {
        self.frames = frames
        let previous = selected
        enumerate()
        guard !items.isEmpty else { return }
        selectedIndex = nearest(to: previous.anchor, kind: previous.kind)
    }

    private mutating func move(_ line: Boundary<ID>, to target: CGFloat) -> BoundaryModeEffect<ID> {
        guard
            let targets = Boundaries.move(
                line, to: target, frames: frames, innerGap: grid.innerGap, minimumSize: minimumSize)
        else { return .ignored }

        let previous = selected
        var anchor = previous.anchor
        if line.axis == .horizontal { anchor.x = target } else { anchor.y = target }
        frames.merge(targets) { $1 }
        enumerate()
        if !items.isEmpty {
            selectedIndex = nearest(to: anchor, kind: previous.kind)
        }
        return .apply(targets)
    }

    private mutating func type(_ character: Character) -> BoundaryModeEffect<ID> {
        let candidate = typed + String(character).lowercased()
        let labels = labels
        if let index = labels.firstIndex(of: candidate) {
            typed = ""
            selectedIndex = index
            return .updated
        }
        guard labels.contains(where: { $0.hasPrefix(candidate) }) else {
            typed = ""
            return .ignored
        }
        typed = candidate
        return .updated
    }

    private mutating func enumerate() {
        let found = Boundaries.all(frames: frames, grid: grid)
        items = found.boundaries.map(BoundaryItem.boundary) + found.crosspoints.map(BoundaryItem.crosspoint)
        typed = ""
    }

    /// Prefers boundaries of the focused window, nearest to its center.
    private func initialSelection(focused: ID?) -> Int {
        guard let focused, let frame = frames[focused] else { return 0 }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let candidates = items.indices.filter {
            if case .boundary(let boundary) = items[$0] { boundary.members.contains(focused) } else { false }
        }
        let pool = candidates.isEmpty ? Array(items.indices) : candidates
        return pool.min { distance(items[$0], to: center) < distance(items[$1], to: center) } ?? 0
    }

    private func nearest(to point: CGPoint, kind: Int) -> Int {
        let sameKind = items.indices.filter { items[$0].kind == kind }
        let pool = sameKind.isEmpty ? Array(items.indices) : sameKind
        return pool.min { hypot(items[$0].anchor, point) < hypot(items[$1].anchor, point) } ?? 0
    }

    /// Distance from `point` to the item: to the line segment for a boundary.
    private func distance(_ item: BoundaryItem<ID>, to point: CGPoint) -> CGFloat {
        guard case .boundary(let boundary) = item else { return hypot(item.anchor, point) }
        let along = boundary.axis.perpendicular
        let alongValue = along == .horizontal ? point.x : point.y
        let acrossValue = along == .horizontal ? point.y : point.x
        let clamped = alongValue.clamped(to: boundary.extent)
        return hypot(alongValue - clamped, acrossValue - boundary.position)
    }
}

private func hypot(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}
