import CoreGraphics
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
    let main = Display(
        id: "main", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 30, width: 1440, height: 870))
    let external = Display(
        id: "ext", frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1440))

    @Test func maximizeFillsTheWindowsDisplay() {
        let system = FakeWindowSystem(
            frames: [1: CGRect(x: 2000, y: 200, width: 500, height: 400)], focused: 1, screens: [main, external])
        let executor = CommandExecutor(system: system, outerGap: 8)

        #expect(executor.execute(.maximize))
        #expect(system.frames[1] == CGRect(x: 1448, y: 8, width: 2544, height: 1424))
    }

    @Test func noFocusedWindowIsANoOp() {
        let system = FakeWindowSystem(frames: [:], focused: nil, screens: [main])
        #expect(!CommandExecutor(system: system).execute(.maximize))
    }
}
