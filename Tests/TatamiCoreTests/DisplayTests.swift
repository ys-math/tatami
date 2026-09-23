import CoreGraphics
import Testing

@testable import TatamiCore

struct CoordinatesTests {
    @Test func flipOnPrimaryDisplay() {
        // A 100pt-tall rect at the bottom of a 1000pt-tall primary display is at the top in AX space.
        let appKit = CGRect(x: 10, y: 0, width: 200, height: 100)
        #expect(Coordinates.flip(appKit, primaryHeight: 1000) == CGRect(x: 10, y: 900, width: 200, height: 100))
    }

    @Test func flipIsItsOwnInverse() {
        let rect = CGRect(x: -1920, y: 312, width: 1920, height: 1080)
        #expect(Coordinates.flip(Coordinates.flip(rect, primaryHeight: 1117), primaryHeight: 1117) == rect)
    }

    @Test func flipDisplayAbovePrimary() {
        // A display stacked above a 1000pt primary has AppKit y = 1000; in AX it has negative y.
        let above = CGRect(x: 0, y: 1000, width: 1600, height: 900)
        #expect(Coordinates.flip(above, primaryHeight: 1000).minY == -900)
    }
}

struct DisplayTests {
    let left = Display(
        id: "L", frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 775))
    let right = Display(
        id: "R", frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800))

    @Test func picksDisplayWithLargestOverlap() {
        let window = CGRect(x: 900, y: 100, width: 400, height: 300)
        #expect(Display.containing(window, in: [left, right])?.id == "R")
    }

    @Test func picksNearestDisplayWhenOffScreen() {
        let window = CGRect(x: -500, y: 100, width: 200, height: 200)
        #expect(Display.containing(window, in: [left, right])?.id == "L")
    }

    @Test func noDisplays() {
        #expect(Display.containing(.zero, in: []) == nil)
    }
}

struct PresetsTests {
    @Test func maximizeInsetsVisibleFrameByOuterGap() {
        let display = Display(
            id: "D", frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 775))
        #expect(Presets.maximize(on: display, outerGap: 8) == CGRect(x: 8, y: 33, width: 984, height: 759))
    }
}
