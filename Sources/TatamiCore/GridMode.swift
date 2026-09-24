/// Hint labels for grid cells.
///
/// Labels never use `h j k l` (cursor keys), `-`/`=` (grid size) or the
/// keys grid mode reserves (Tab, Return, Escape).
public enum GridLabels {
    /// Left-hand keyboard rows, used when the grid fits (up to 5x3) so labels
    /// mirror the cell layout.
    static let spatialRows = ["qwert", "asdfg", "zxcvb"]
    static let alphabet = Array("asdfgqwertyuiopzxcvbnm1234567890").map(String.init)

    /// One label per cell, in row-major order. Single characters when they
    /// suffice, otherwise two-character labels of equal length.
    public static func labels(for size: GridSize) -> [String] {
        if size.rows <= spatialRows.count, size.columns <= spatialRows[0].count {
            return (0..<size.rows).flatMap { row in
                spatialRows[row].prefix(size.columns).map(String.init)
            }
        }
        if size.cellCount <= alphabet.count {
            return Array(alphabet.prefix(size.cellCount))
        }
        let n = alphabet.count
        return (0..<size.cellCount).map { alphabet[$0 / n] + alphabet[$0 % n] }
    }
}

/// Keyboard input to grid mode, already decoded from key events.
public enum GridModeInput: Equatable, Sendable {
    /// `hjkl`: move the selection one cell.
    case move(Direction)
    /// `HJKL`: resize the selection with the tmux-style rule.
    case resize(Direction)
    /// A label character.
    case character(Character)
    /// `-`/`=` (columns) and `_`/`+` (rows).
    case adjustGrid(columns: Int, rows: Int)
    /// Tab: continue on the next display.
    case nextDisplay
    /// Return.
    case apply
    /// Escape or a click.
    case cancel
}

public enum GridModeEffect: Equatable, Sendable {
    /// State changed; redraw.
    case updated
    /// The input did nothing (e.g. an unknown label or a move at the edge).
    case ignored
    /// The grid of a display changed size and should be persisted.
    case gridChanged(displayIndex: Int, GridSize)
    /// Place the window on `span` of the display and leave grid mode.
    case apply(displayIndex: Int, CellSpan)
    /// Leave grid mode without changes.
    case cancel
}

/// The state of the modal grid overlay. Pure: the app feeds it decoded
/// input and acts on the returned effect.
public struct GridModeState: Equatable, Sendable {
    public private(set) var displayIndex: Int
    /// Grid size of every display, indexed like the app's display list.
    public private(set) var gridSizes: [GridSize]
    public private(set) var selection: CellSpan
    /// The first cell picked by label; the next label completes the span.
    public private(set) var corner: CellSpan?
    /// Characters typed towards a multi-character label.
    public private(set) var typed = ""

    public init(displayIndex: Int, gridSizes: [GridSize], selection: CellSpan) {
        precondition(gridSizes.indices.contains(displayIndex))
        self.displayIndex = displayIndex
        self.gridSizes = gridSizes
        self.selection = selection
    }

    public var gridSize: GridSize { gridSizes[displayIndex] }
    public var labels: [String] { GridLabels.labels(for: gridSize) }

    public mutating func handle(_ input: GridModeInput) -> GridModeEffect {
        switch input {
        case .move(let direction):
            return updateSelection(GridCommands.move(selection, direction, in: gridSize))
        case .resize(let direction):
            return updateSelection(GridCommands.resize(selection, direction, in: gridSize))
        case .character(let character):
            return type(character)
        case .adjustGrid(let columns, let rows):
            let old = gridSize
            let new = GridSize(columns: old.columns + columns, rows: old.rows + rows)
            guard new != old else { return .ignored }
            gridSizes[displayIndex] = new
            selection = GridCommands.map(selection, from: old, to: new)
            resetTyping()
            return .gridChanged(displayIndex: displayIndex, new)
        case .nextDisplay:
            guard gridSizes.count > 1 else { return .ignored }
            let old = gridSize
            displayIndex = (displayIndex + 1) % gridSizes.count
            selection = GridCommands.map(selection, from: old, to: gridSize)
            resetTyping()
            return .updated
        case .apply:
            return .apply(displayIndex: displayIndex, selection)
        case .cancel:
            return .cancel
        }
    }

    private mutating func updateSelection(_ span: CellSpan?) -> GridModeEffect {
        resetTyping()
        guard let span else { return .ignored }
        selection = span
        return .updated
    }

    private mutating func type(_ character: Character) -> GridModeEffect {
        let candidate = typed + String(character).lowercased()
        let labels = labels
        if let index = labels.firstIndex(of: candidate) {
            typed = ""
            let cell = CellSpan.cell(index, in: gridSize)
            if let corner {
                return .apply(displayIndex: displayIndex, corner.union(cell))
            }
            corner = cell
            selection = cell
            return .updated
        }
        guard labels.contains(where: { $0.hasPrefix(candidate) }) else {
            typed = ""
            return .ignored
        }
        typed = candidate
        return .updated
    }

    private mutating func resetTyping() {
        typed = ""
        corner = nil
    }
}
