import Foundation

/// Per-display grid sizes, keyed by display UUID. Stored in `~/.config/tatami/state.json`.
public struct GridState: Codable, Sendable, Equatable {
    public var grids: [String: GridSize]

    public init(grids: [String: GridSize] = [:]) {
        self.grids = grids
    }

    public func size(for displayID: String, default defaultSize: GridSize) -> GridSize {
        grids[displayID] ?? defaultSize
    }

    public mutating func set(_ size: GridSize, for displayID: String) {
        grids[displayID] = size
    }

    /// Adds `delta` columns and rows to a display's grid, within `GridSize.limits`.
    /// Returns the new size.
    @discardableResult
    public mutating func adjust(
        _ displayID: String, columns: Int = 0, rows: Int = 0, default defaultSize: GridSize
    ) -> GridSize {
        let current = size(for: displayID, default: defaultSize)
        let new = GridSize(columns: current.columns + columns, rows: current.rows + rows)
        grids[displayID] = new
        return new
    }
}
