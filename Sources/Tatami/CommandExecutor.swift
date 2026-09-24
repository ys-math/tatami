import CoreGraphics
import TatamiCore

/// Turns actions into frame changes: snapshot the focused window, ask
/// `TatamiCore` for the target frame, apply it.
@MainActor
final class CommandExecutor<System: WindowSystem> {
    let system: System
    var config: Config
    private(set) var gridState: GridState
    /// Called after a grid size changes, for persistence.
    var onGridStateChange: (GridState) -> Void = { _ in }
    /// Called after every grid adjustment, even at the size limit, to show the grid.
    var onGridAdjusted: (Grid, Display) -> Void = { _, _ in }

    init(system: System, config: Config = .default, gridState: GridState = GridState()) {
        self.system = system
        self.config = config
        self.gridState = gridState
    }

    /// Returns `false` when there was nothing to do (no window, at an edge, ...).
    @discardableResult
    func execute(_ action: Action) -> Bool {
        guard let window = system.focusedWindow(),
            let current = system.frame(of: window),
            let display = Display.containing(current, in: system.displays())
        else { return false }

        let gaps = config.gaps
        let grid = Grid(
            size: gridState.size(for: display.id, default: config.defaultGrid), display: display, gaps: gaps)
        let span = grid.span(nearest: current)

        let target: CGRect?
        switch action {
        case .moveLeft: target = GridCommands.move(span, .left, in: grid).map(grid.rect(for:))
        case .moveDown: target = GridCommands.move(span, .down, in: grid).map(grid.rect(for:))
        case .moveUp: target = GridCommands.move(span, .up, in: grid).map(grid.rect(for:))
        case .moveRight: target = GridCommands.move(span, .right, in: grid).map(grid.rect(for:))
        case .leftHalf: target = Presets.leftHalf(on: display, gaps: gaps)
        case .rightHalf: target = Presets.rightHalf(on: display, gaps: gaps)
        case .maximize: target = Presets.maximize(on: display, gaps: gaps)
        case .center: target = Presets.center(current, on: display, gaps: gaps)
        case .split: target = GridCommands.split(span, in: grid).map(grid.rect(for:))
        case .gridColumnsDecrease: return adjustGrid(display, columns: -1)
        case .gridColumnsIncrease: return adjustGrid(display, columns: 1)
        case .gridRowsDecrease: return adjustGrid(display, rows: -1)
        case .gridRowsIncrease: return adjustGrid(display, rows: 1)
        case .resizeLeft: return joinedResize(window, current, .left, display: display, grid: grid)
        case .resizeDown: return joinedResize(window, current, .down, display: display, grid: grid)
        case .resizeUp: return joinedResize(window, current, .up, display: display, grid: grid)
        case .resizeRight: return joinedResize(window, current, .right, display: display, grid: grid)
        case .gridMode, .boundaryMode: return false  // Modal; handled by their controllers.
        case .resizeAloneLeft: return resizeAlone(window, current, .left, grid: grid)
        case .resizeAloneDown: return resizeAlone(window, current, .down, grid: grid)
        case .resizeAloneUp: return resizeAlone(window, current, .up, grid: grid)
        case .resizeAloneRight: return resizeAlone(window, current, .right, grid: grid)
        case .growLeft: return resizeEdge(window, current, .left, grow: true, grid: grid)
        case .growDown: return resizeEdge(window, current, .down, grow: true, grid: grid)
        case .growUp: return resizeEdge(window, current, .up, grow: true, grid: grid)
        case .growRight: return resizeEdge(window, current, .right, grow: true, grid: grid)
        case .shrinkLeft: return resizeEdge(window, current, .left, grow: false, grid: grid)
        case .shrinkDown: return resizeEdge(window, current, .down, grow: false, grid: grid)
        case .shrinkUp: return resizeEdge(window, current, .up, grow: false, grid: grid)
        case .shrinkRight: return resizeEdge(window, current, .right, grow: false, grid: grid)
        }

        guard let target else {
            // At an edge or unsplittable: still snap an unaligned window so the
            // command visibly takes effect on the grid.
            let snapped = grid.rect(for: span)
            return snapped != current && system.setFrame(snapped, of: window)
        }
        return system.setFrame(target, of: window)
    }

    /// Moves the boundary on one side of the focused window, together with
    /// every window joined to it on this display.
    private func joinedResize(
        _ window: System.Window, _ current: CGRect, _ direction: Direction, display: Display, grid: Grid
    ) -> Bool {
        var frames = frames(on: display)
        frames[window] = current

        guard
            let targets = Boundaries.joinedResize(
                window, direction, frames: frames, grid: grid, minimumSize: config.minimumWindowSize.cgSize)
        else { return false }
        return apply(targets, originals: frames)
    }

    /// Tmux-style resize of the focused window only, ignoring neighbours.
    private func resizeAlone(_ window: System.Window, _ current: CGRect, _ direction: Direction, grid: Grid) -> Bool {
        guard
            let targets = Boundaries.joinedResize(
                window, direction, frames: [window: current], grid: grid,
                minimumSize: config.minimumWindowSize.cgSize, joined: false)
        else { return false }
        return apply(targets, originals: [window: current])
    }

    /// Moves one named edge of the focused window only.
    private func resizeEdge(
        _ window: System.Window, _ current: CGRect, _ edge: Direction, grow: Bool, grid: Grid
    ) -> Bool {
        guard
            let target = Boundaries.resizeEdge(
                current, edge, grow: grow, grid: grid, minimumSize: config.minimumWindowSize.cgSize)
        else { return false }
        return apply([window: target], originals: [window: current])
    }

    /// Frames of the standard windows whose largest part is on `display`.
    func frames(on display: Display) -> [System.Window: CGRect] {
        var frames: [System.Window: CGRect] = [:]
        let displays = system.displays()
        for window in system.windows() {
            guard let frame = system.frame(of: window),
                Display.containing(frame, in: displays)?.id == display.id
            else { continue }
            frames[window] = frame
        }
        return frames
    }

    /// Sets several frames as one change. If any window ends up far from its
    /// target (the app refused or clamped the size), every window is put back.
    @discardableResult
    func apply(_ targets: [System.Window: CGRect], originals: [System.Window: CGRect]) -> Bool {
        for (window, frame) in targets {
            system.setFrame(frame, of: window)
        }
        let complied = targets.allSatisfy { window, target in
            guard let actual = system.frame(of: window) else { return false }
            return actual.isClose(to: target, tolerance: Self.complianceTolerance)
        }
        guard complied else {
            for window in targets.keys {
                if let original = originals[window] {
                    system.setFrame(original, of: window)
                }
            }
            return false
        }
        return true
    }

    /// Apps that size in steps (e.g. terminals snapping to character cells)
    /// may land a little off target; anything further is treated as a refusal.
    static var complianceTolerance: CGFloat { 24 }

    func gridSize(for display: Display) -> GridSize {
        gridState.size(for: display.id, default: config.defaultGrid)
    }

    func grid(for display: Display) -> Grid {
        Grid(size: gridSize(for: display), display: display, gaps: config.gaps)
    }

    func setGridSize(_ size: GridSize, for display: Display) {
        gridState.set(size, for: display.id)
        onGridStateChange(gridState)
    }

    /// Changes the grid of `display` without moving any window.
    private func adjustGrid(_ display: Display, columns: Int = 0, rows: Int = 0) -> Bool {
        let before = gridState.size(for: display.id, default: config.defaultGrid)
        let after = gridState.adjust(display.id, columns: columns, rows: rows, default: config.defaultGrid)
        onGridAdjusted(Grid(size: after, display: display, gaps: config.gaps), display)
        guard after != before else { return false }
        onGridStateChange(gridState)
        return true
    }
}

extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(maxX - other.maxX) <= tolerance && abs(maxY - other.maxY) <= tolerance
    }
}
