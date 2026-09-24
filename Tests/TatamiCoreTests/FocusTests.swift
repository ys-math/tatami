import CoreGraphics
import Testing

@testable import TatamiCore

private func display(_ id: String, _ x: CGFloat, _ width: CGFloat) -> Display {
    let frame = CGRect(x: x, y: 0, width: width, height: 1000)
    return Display(id: id, frame: frame, visibleFrame: frame)
}

private let left = display("left", 0, 1000)
private let right = display("right", 1000, 1000)

struct FocusNavigationTests {
    let windows: [String: CGRect] = [
        "A": CGRect(x: 0, y: 0, width: 500, height: 1000),
        "B": CGRect(x: 500, y: 0, width: 500, height: 500),
        "C": CGRect(x: 500, y: 500, width: 500, height: 500),
        // On the right display: one near its left edge at the bottom, one far right at the top.
        "D": CGRect(x: 1000, y: 600, width: 400, height: 400),
        "E": CGRect(x: 1600, y: 0, width: 400, height: 400),
    ]

    @Test func staysOnTheDisplayWhileThereIsANeighbour() {
        #expect(FocusNavigation.next(from: "A", .right, windows: windows, displays: [left, right]) == "B")
        #expect(FocusNavigation.next(from: "B", .down, windows: windows, displays: [left, right]) == "C")
        #expect(FocusNavigation.next(from: "C", .left, windows: windows, displays: [left, right]) == "A")
    }

    @Test func crossesToTheWindowNearestTheEnteringEdge() {
        #expect(FocusNavigation.next(from: "B", .right, windows: windows, displays: [left, right]) == "D")
        // D has nothing to its left on its display: B and C touch the entering edge; C is level with D.
        #expect(FocusNavigation.next(from: "D", .left, windows: windows, displays: [left, right]) == "C")
    }

    @Test func noDisplayBeyondTheEdge() {
        #expect(FocusNavigation.next(from: "A", .left, windows: windows, displays: [left, right]) == nil)
    }
}

struct FocusHintStateTests {
    @Test func labelsGoDisplayByDisplayInReadingOrder() throws {
        let frames: [String: CGRect] = [
            "onRight": CGRect(x: 1100, y: 0, width: 400, height: 400),
            "bottomLeft": CGRect(x: 0, y: 600, width: 400, height: 400),
            "topLeft": CGRect(x: 0, y: 0, width: 400, height: 400),
        ]
        let state = try #require(FocusHintState(frames: frames, displays: [right, left]))
        #expect(state.windows == ["topLeft", "bottomLeft", "onRight"])
        #expect(state.labels == ["a", "s", "d"])
    }

    @Test func typingALabelFocusesItsWindow() throws {
        var state = try #require(
            FocusHintState(frames: ["A": CGRect(x: 0, y: 0, width: 100, height: 100)], displays: [left]))
        #expect(state.type("z") == .ignored)
        #expect(state.type("A") == .focus("A"))
    }

    @Test func stackedWindowsGetSeparateLabelPositions() throws {
        let frames: [String: CGRect] = [
            "back": CGRect(x: 100, y: 100, width: 600, height: 400),
            "front": CGRect(x: 110, y: 110, width: 600, height: 400),
        ]
        let state = try #require(FocusHintState(frames: frames, displays: [left]))
        let distance = hypot(state.positions[0].x - state.positions[1].x, state.positions[0].y - state.positions[1].y)
        #expect(distance >= 44)
    }

    @Test func noWindowsNoHints() {
        #expect(FocusHintState<String>(frames: [:], displays: [left]) == nil)
    }
}
