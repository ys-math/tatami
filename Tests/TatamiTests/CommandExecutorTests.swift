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
    /// Simulates apps that refuse to become narrower than this.
    var minimumWidths: [Int: CGFloat] = [:]
    /// Front-to-back order; defaults to ascending IDs.
    var order: [Int]?
    var fixedSize: Set<Int> = []
    var apps: [Int: String] = [:]

    init(frames: [Int: CGRect], focused: Int?, screens: [Display]) {
        self.frames = frames
        self.focused = focused
        self.screens = screens
    }

    func focusedWindow() -> Int? { focused }
    func windows() -> [Int] { order ?? frames.keys.sorted() }
    func isResizable(_ window: Int) -> Bool { !fixedSize.contains(window) }
    func appIdentifier(of window: Int) -> String? { apps[window] }
    func frame(of window: Int) -> CGRect? { frames[window] }
    func setFrame(_ frame: CGRect, of window: Int) -> Bool {
        var frame = frame
        if let minimum = minimumWidths[window], frame.width < minimum {
            frame.size.width = minimum
        }
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
        var shown: [(Grid, Display)] = []
        executor.onGridAdjusted = { shown.append(($0, $1)) }
        #expect(!executor.execute(.gridColumnsDecrease))
        // The grid is still shown so the user sees the limit was reached.
        #expect(shown.map(\.0.size) == [GridSize(columns: 1, rows: 1)])
        #expect(shown.map(\.1.id) == ["main"])
    }
}

@MainActor
struct ResizeExecutorTests {
    let main = Display(
        id: "main", frame: CGRect(x: 0, y: 0, width: 1016, height: 540),
        visibleFrame: CGRect(x: 0, y: 24, width: 1016, height: 516))
    let external = Display(
        id: "ext", frame: CGRect(x: 1016, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1016, y: 0, width: 2560, height: 1440))
    /// Main display grid: 4x2 over x 8–1008; columns 8–252, 260–504, 512–756, 764–1008.
    var grid: Grid { Grid(size: .default, display: main, gaps: Gaps(outer: 8, inner: 8)) }

    private func span(_ column: Int, _ columns: Int) -> CGRect {
        grid.rect(for: CellSpan(column: column, row: 0, columnCount: columns, rowCount: 2))
    }

    @Test func joinedResizeMovesNeighboursOnTheSameDisplayOnly() {
        let otherDisplay = CGRect(x: 1100, y: 100, width: 500, height: 500)
        let system = FakeWindowSystem(
            frames: [1: span(0, 2), 2: span(2, 2), 3: otherDisplay], focused: 1, screens: [main, external])
        let executor = CommandExecutor(system: system)

        #expect(executor.execute(.resizeRight))
        #expect(system.frames[1]?.maxX == 756)
        #expect(system.frames[2]?.minX == 764 && system.frames[2]?.maxX == 1008)
        #expect(system.frames[3] == otherDisplay)
    }

    @Test func refusedResizeIsRevertedForEveryWindow() {
        let system = FakeWindowSystem(frames: [1: span(0, 2), 2: span(2, 2)], focused: 1, screens: [main])
        system.minimumWidths[2] = 400  // B cannot shrink to one column (244pt).
        let executor = CommandExecutor(system: system)

        #expect(!executor.execute(.resizeRight))
        #expect(system.frames[1] == span(0, 2))
        #expect(system.frames[2] == span(2, 2))
    }

    @Test func separateResizeIgnoresNeighbours() {
        let system = FakeWindowSystem(frames: [1: span(0, 2), 2: span(2, 2)], focused: 1, screens: [main])
        let executor = CommandExecutor(system: system)

        #expect(executor.execute(.growRight))
        #expect(system.frames[1]?.maxX == 756)
        #expect(system.frames[2] == span(2, 2))

        #expect(executor.execute(.shrinkRight))
        #expect(executor.execute(.shrinkRight))
        #expect(system.frames[1]?.maxX == 252)
    }

    @Test func resizeAloneGrowsAndShrinksWithOneModifierSet() {
        let system = FakeWindowSystem(frames: [1: span(0, 2), 2: span(2, 2)], focused: 1, screens: [main])
        let executor = CommandExecutor(system: system)

        #expect(executor.execute(.resizeAloneRight))
        #expect(system.frames[1]?.maxX == 756)
        #expect(system.frames[2] == span(2, 2))
        #expect(executor.execute(.resizeAloneLeft))
        #expect(executor.execute(.resizeAloneLeft))
        #expect(system.frames[1]?.maxX == 252)
    }

    @Test func minimumWindowSizeFromConfig() {
        let system = FakeWindowSystem(frames: [1: span(0, 2), 2: span(2, 2)], focused: 1, screens: [main])
        let executor = CommandExecutor(system: system)
        executor.config.minimumWindowSize = Config.Size(width: 300, height: 60)
        #expect(!executor.execute(.resizeRight))
        #expect(!executor.execute(.shrinkRight))
        #expect(system.frames[1] == span(0, 2))
    }
}

@MainActor
struct ArrangeExecutorTests {
    let main = Display(
        id: "main", frame: CGRect(x: 0, y: 0, width: 1016, height: 540),
        visibleFrame: CGRect(x: 0, y: 24, width: 1016, height: 516))
    let external = Display(
        id: "ext", frame: CGRect(x: 1016, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1016, y: 0, width: 2560, height: 1440))
    /// Main display area after the 8pt outer gap.
    let area = CGRect(x: 8, y: 32, width: 1000, height: 500)

    private func system(_ frames: [Int: CGRect], focused: Int) -> FakeWindowSystem {
        FakeWindowSystem(frames: frames, focused: focused, screens: [main, external])
    }

    private let small = CGRect(x: 100, y: 100, width: 300, height: 200)

    @Test func focusedWindowGetsTheMasterSlotThenFrontToBack() {
        let system = system([1: small, 2: small, 3: small], focused: 3)
        system.order = [2, 3, 1]
        let executor = CommandExecutor(system: system)
        var named: [Layout] = []
        executor.onArranged = { layout, _ in named.append(layout) }

        #expect(executor.execute(.arrange))
        let expected = Layout.balancedGrid.frames(count: 3, in: area, gap: 8)
        #expect(system.frames[3] == expected[0])
        #expect(system.frames[2] == expected[1])
        #expect(system.frames[1] == expected[2])
        #expect(named == [.balancedGrid])
    }

    @Test func pressingAgainCyclesAndPreviousGoesBack() {
        let system = system([1: small, 2: small], focused: 1)
        let executor = CommandExecutor(system: system)
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        executor.now = { clock }
        var named: [Layout] = []
        executor.onArranged = { layout, _ in named.append(layout) }

        executor.execute(.arrange)
        clock += 1
        executor.execute(.arrange)
        clock += 1
        executor.execute(.arrangePrevious)
        clock += 10
        executor.execute(.arrange)  // Too late to cycle: reuse the remembered layout.
        #expect(named == [.balancedGrid, .masterStack, .balancedGrid, .balancedGrid])
        #expect(system.frames[1] == Layout.balancedGrid.frames(count: 2, in: area, gap: 8)[0])
    }

    @Test func skipsIneligibleWindowsAndOtherDisplays() {
        let otherDisplay = CGRect(x: 1200, y: 100, width: 500, height: 400)
        let tiny = CGRect(x: 50, y: 50, width: 80, height: 40)
        let system = system([1: small, 2: small, 3: small, 4: tiny, 5: otherDisplay], focused: 1)
        system.fixedSize = [2]
        system.apps = [3: "com.example.ignored"]
        let executor = CommandExecutor(system: system)
        executor.config.ignoredApps = ["com.example.ignored"]

        #expect(executor.execute(.arrange))
        #expect(system.frames[1] == area)  // The only eligible window fills the display.
        #expect(system.frames[2] == small && system.frames[3] == small)
        #expect(system.frames[4] == tiny && system.frames[5] == otherDisplay)
    }

    @Test func arrangeAllDisplaysKeepsWindowsOnTheirDisplay() {
        let onExternal = CGRect(x: 1200, y: 100, width: 500, height: 400)
        let system = system([1: small, 2: onExternal, 3: onExternal.offsetBy(dx: 600, dy: 0)], focused: 1)
        let executor = CommandExecutor(system: system)

        #expect(executor.execute(.arrangeAllDisplays))
        #expect(system.frames[1] == area)
        let externalArea = external.visibleFrame.insetBy(dx: 8, dy: 8)
        let expected = Layout.balancedGrid.frames(count: 2, in: externalArea, gap: 8)
        #expect(Set([system.frames[2]!, system.frames[3]!]) == Set(expected))
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
