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
        }

        guard let target else {
            // At an edge or unsplittable: still snap an unaligned window so the
            // command visibly takes effect on the grid.
            let snapped = grid.rect(for: span)
            return snapped != current && system.setFrame(snapped, of: window)
        }
        return system.setFrame(target, of: window)
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
