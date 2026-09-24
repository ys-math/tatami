import CoreGraphics
import Foundation
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
    /// Called after auto-arrange lays out a display, to name the layout.
    var onArranged: (Layout, Display) -> Void = { _, _ in }
    /// The clock used for arrange cycling; replaced in tests.
    var now: () -> Date = Date.init
    private var arrangeHistory = ArrangeHistory<System.Window>()

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
        case .moveLeft: target = move(span, .left, grid: grid, display: display)
        case .moveDown: target = move(span, .down, grid: grid, display: display)
        case .moveUp: target = move(span, .up, grid: grid, display: display)
        case .moveRight: target = move(span, .right, grid: grid, display: display)
        case .sendToNextDisplay: target = send(span, grid: grid, display: display, step: 1)
        case .sendToPreviousDisplay: target = send(span, grid: grid, display: display, step: -1)
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
        case .gridMode, .boundaryMode, .windowCommand: return false  // Modal; handled by their controllers.
        case .swapLeft: return swap(window, .left, display: display)
        case .swapDown: return swap(window, .down, display: display)
        case .swapUp: return swap(window, .up, display: display)
        case .swapRight: return swap(window, .right, display: display)
        case .rotateClockwise: return rotate(display, focused: window, clockwise: true)
        case .rotateCounterclockwise: return rotate(display, focused: window, clockwise: false)
        case .swapWithMain: return swapWithMain(window, display: display)
        case .arrange: return arrange(display, focused: window, step: 1)
        case .arrangePrevious: return arrange(display, focused: window, step: -1)
        case .arrangeAllDisplays: return arrangeAllDisplays(focused: window)
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

    // MARK: - Swap and rotate

    /// Frames of the windows that may trade places on `display` (the auto-arrange set).
    func swappableFrames(on display: Display, focused: System.Window) -> [System.Window: CGRect] {
        var frames: [System.Window: CGRect] = [:]
        for window in arrangeableWindows(on: display, focused: focused) {
            frames[window] = system.frame(of: window)
        }
        return frames
    }

    private func swap(_ window: System.Window, _ direction: Direction, display: Display) -> Bool {
        let frames = swappableFrames(on: display, focused: window)
        guard let other = Swaps.neighbor(of: window, direction, frames: frames),
            let targets = Swaps.swap(window, other, frames: frames)
        else { return false }
        return apply(targets, originals: frames)
    }

    private func rotate(_ display: Display, focused: System.Window, clockwise: Bool) -> Bool {
        let frames = swappableFrames(on: display, focused: focused)
        guard let targets = Swaps.rotate(frames, clockwise: clockwise) else { return false }
        return apply(targets, originals: frames)
    }

    /// Rotates just `group` one slot around its own center (two windows: a swap).
    @discardableResult
    func rotate(group: Set<System.Window>, clockwise: Bool) -> Bool {
        var frames: [System.Window: CGRect] = [:]
        for window in group {
            frames[window] = system.frame(of: window)
        }
        guard frames.count == group.count, let targets = Swaps.rotate(frames, clockwise: clockwise) else {
            return false
        }
        return apply(targets, originals: frames)
    }

    private func swapWithMain(_ window: System.Window, display: Display) -> Bool {
        let frames = swappableFrames(on: display, focused: window)
        // Plain front-to-back order (not focused-first), so size ties go to the frontmost window.
        let frontToBack = system.windows().filter { frames[$0] != nil }
        guard let partner = Swaps.mainPartner(of: window, frames: frames, order: frontToBack),
            let targets = Swaps.swap(window, partner, frames: frames)
        else { return false }
        return apply(targets, originals: frames)
    }

    // MARK: - Displays

    /// One cell in `direction`; past the display's edge, onto the adjacent display.
    private func move(_ span: CellSpan, _ direction: Direction, grid: Grid, display: Display) -> CGRect? {
        if let moved = GridCommands.move(span, direction, in: grid) {
            return grid.rect(for: moved)
        }
        guard let next = Display.adjacent(to: display, direction, in: system.displays()) else { return nil }
        let nextGrid = self.grid(for: next)
        return nextGrid.rect(for: GridCommands.cross(span, direction, from: grid.size, to: nextGrid.size))
    }

    /// The same relative cells on the next or previous display in physical order (wrapping).
    private func send(_ span: CellSpan, grid: Grid, display: Display, step: Int) -> CGRect? {
        let displays = Display.sortedPhysically(system.displays())
        guard displays.count > 1, let index = displays.firstIndex(where: { $0.id == display.id }) else { return nil }
        let next = displays[(index + step + displays.count) % displays.count]
        let nextGrid = self.grid(for: next)
        return nextGrid.rect(for: GridCommands.map(span, from: grid.size, to: nextGrid.size))
    }

    // MARK: - Auto-arrange

    /// Lays out the display's eligible windows, cycling layouts on repeated presses.
    private func arrange(_ display: Display, focused: System.Window, step: Int) -> Bool {
        let windows = arrangeableWindows(on: display, focused: focused)
        guard !windows.isEmpty else { return false }
        let area = grid(for: display).area
        let layout = arrangeHistory.layout(
            display: display.id, windows: Set(windows), available: Layout.available(for: area), step: step,
            now: now(), timeout: config.cycleTimeout)
        place(windows, in: area, layout: layout)
        onArranged(layout, display)
        return true
    }

    /// Lays out every display with its remembered layout. Windows stay on their display.
    private func arrangeAllDisplays(focused: System.Window) -> Bool {
        var arranged = false
        for display in system.displays() {
            let windows = arrangeableWindows(on: display, focused: focused)
            guard !windows.isEmpty else { continue }
            let area = grid(for: display).area
            let available = Layout.available(for: area)
            let remembered = arrangeHistory.rememberedLayout(for: display.id)
            let layout = remembered.flatMap { available.contains($0) ? $0 : nil } ?? available[0]
            place(windows, in: area, layout: layout)
            arranged = true
        }
        return arranged
    }

    private func place(_ windows: [System.Window], in area: CGRect, layout: Layout) {
        let frames = layout.frames(count: windows.count, in: area, gap: config.innerGap)
        for (window, frame) in zip(windows, frames) {
            // Each window on its own: an app that refuses its slot should not undo the others.
            system.setFrame(frame, of: window)
        }
    }

    /// Windows auto-arrange may move on `display`: resizable, not tiny, not
    /// ignored; the focused window first, then front to back.
    func arrangeableWindows(on display: Display, focused: System.Window) -> [System.Window] {
        let displays = system.displays()
        let minimum = config.minimumWindowSize
        let ignored = Set(config.ignoredApps)
        var windows = system.windows().filter { window in
            guard let frame = system.frame(of: window),
                Display.containing(frame, in: displays)?.id == display.id,
                frame.width >= minimum.width, frame.height >= minimum.height,
                system.isResizable(window)
            else { return false }
            return system.appIdentifier(of: window).map { !ignored.contains($0) } ?? true
        }
        if let index = windows.firstIndex(of: focused) {
            windows.insert(windows.remove(at: index), at: 0)
        }
        return windows
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
