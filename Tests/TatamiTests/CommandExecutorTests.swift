import CoreGraphics
import Foundation
import TatamiCore
import Testing

@testable import Tatami

@MainActor
final class FakeWindowSystem: WindowSystem {
    var frames: [Int: CGRect]
    var focused: Int?
    var screens: [Display]

    init(frames: [Int: CGRect], focused: Int?, screens: [Display]) {
        self.frames = frames
        self.focused = focused
        self.screens = screens
    }

    func focusedWindow() -> Int? { focused }
    func frame(of window: Int) -> CGRect? { frames[window] }
    func setFrame(_ frame: CGRect, of window: Int) -> Bool {
        frames[window] = frame
        return true
    }
    func displays() -> [Display] { screens }
}

@MainActor
struct CommandExecutorTests {
    /// Visible area 1016x516 at (0,0) → inset by 8 → 1000x500 at (8,8); 4x2 cells of 244x246 with 8pt gaps.
    let main = Display(
        id: "main", frame: CGRect(x: 0, y: 0, width: 1016, height: 540),
        visibleFrame: CGRect(x: 0, y: 24, width: 1016, height: 516))
    let external = Display(
        id: "ext", frame: CGRect(x: 1016, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1016, y: 0, width: 2560, height: 1440))

    private func executor(window: CGRect) -> (CommandExecutor<FakeWindowSystem>, FakeWindowSystem) {
        let system = FakeWindowSystem(frames: [1: window], focused: 1, screens: [main, external])
        return (CommandExecutor(system: system), system)
    }

    private func grid(_ size: GridSize = .default, on display: Display? = nil) -> Grid {
        Grid(size: size, display: display ?? main, gaps: Gaps(outer: 8, inner: 8))
    }

    @Test func maximizeFillsTheWindowsDisplay() {
        let (executor, system) = executor(window: CGRect(x: 2000, y: 200, width: 500, height: 400))
        #expect(executor.execute(.maximize))
        #expect(system.frames[1] == CGRect(x: 1024, y: 8, width: 2544, height: 1424))
    }

    @Test func noFocusedWindowIsANoOp() {
        let system = FakeWindowSystem(frames: [:], focused: nil, screens: [main])
        #expect(!CommandExecutor(system: system).execute(.maximize))
    }

    @Test func moveSnapsThenShifts() {
        // Roughly the first cell, slightly off-grid.
        let (executor, system) = executor(window: CGRect(x: 20, y: 40, width: 230, height: 230))
        #expect(executor.execute(.moveRight))
        #expect(system.frames[1] == grid().rect(for: CellSpan(column: 1, row: 0, columnCount: 1, rowCount: 1)))
    }

    @Test func moveAtEdgeOnlySnaps() {
        let cell = grid().rect(for: CellSpan(column: 0, row: 0, columnCount: 1, rowCount: 1))
        let (executor, system) = executor(window: cell)
        #expect(!executor.execute(.moveLeft))
        #expect(system.frames[1] == cell)

        let offGrid = cell.offsetBy(dx: 5, dy: 0)
        system.frames[1] = offGrid
        #expect(executor.execute(.moveLeft))
        #expect(system.frames[1] == cell)
    }

    @Test func splitUsesTheDisplaysGrid() {
        let full = grid().rect(for: grid().fullSpan)
        let (executor, system) = executor(window: full)
        #expect(executor.execute(.split))
        #expect(system.frames[1] == grid().rect(for: CellSpan(column: 0, row: 0, columnCount: 2, rowCount: 2)))
    }

    @Test func gridChangesArePerDisplayAndDoNotMoveWindows() {
        let window = CGRect(x: 1100, y: 100, width: 600, height: 400)
        let (executor, system) = executor(window: window)
        var saved: GridState?
        executor.onGridStateChange = { saved = $0 }

        #expect(executor.execute(.gridColumnsIncrease))
        #expect(executor.execute(.gridRowsIncrease))
        #expect(system.frames[1] == window)
        #expect(saved?.grids == ["ext": GridSize(columns: 5, rows: 3)])

        // The next command on that display uses the new grid.
        #expect(executor.execute(.moveLeft))
        let newGrid = grid(GridSize(columns: 5, rows: 3), on: external)
        #expect(newGrid.rect(for: newGrid.span(nearest: system.frames[1]!)) == system.frames[1])
    }

    @Test func gridAtLimitReportsNoChange() {
        let (executor, _) = executor(window: CGRect(x: 10, y: 30, width: 100, height: 100))
        executor.config.defaultGrid = GridSize(columns: 1, rows: 1)
        #expect(!executor.execute(.gridColumnsDecrease))
    }
}

struct SettingsFilesTests {
    private func temporaryFiles() -> SettingsFiles {
        SettingsFiles(directory: FileManager.default.temporaryDirectory.appending(path: "tatami-tests-\(UUID())"))
    }

    @Test func firstLoadWritesDefaults() throws {
        let files = temporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        #expect(try files.loadConfig().get() == Config.default)
        #expect(FileManager.default.fileExists(atPath: files.configURL.path))
    }

    @Test func invalidConfigIsReported() throws {
        let files = temporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try Data(#"{"bindings": {"nope": "ctrl+n"}}"#.utf8).write(to: files.configURL)
        #expect(throws: ConfigError.unknownAction("nope")) { try files.loadConfig().get() }
    }

    @Test func stateRoundTripsAndToleratesMissingFile() throws {
        let files = temporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        #expect(files.loadState() == GridState())
        let state = GridState(grids: ["X": GridSize(columns: 3, rows: 3)])
        try files.saveState(state)
        #expect(files.loadState() == state)
    }
}
