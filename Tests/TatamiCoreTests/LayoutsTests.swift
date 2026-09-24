import CoreGraphics
import Foundation
import Testing

@testable import TatamiCore

private let landscape = CGRect(x: 8, y: 33, width: 1600, height: 900)
private let ultrawide = CGRect(x: 0, y: 0, width: 3440, height: 1400)
private let portrait = CGRect(x: 0, y: 0, width: 900, height: 1600)
private let gap: CGFloat = 8
private let epsilon: CGFloat = 0.01

struct LayoutInvariantTests {
    static let cases: [(Layout, Int)] = Layout.allCases.flatMap { layout in (1...12).map { (layout, $0) } }

    @Test(arguments: cases)
    func framesTileTheAreaWithoutOverlap(layout: Layout, count: Int) {
        let area = layout == .centeredMaster ? ultrawide : landscape
        let frames = layout.frames(count: count, in: area, gap: gap)
        #expect(frames.count == count)
        for frame in frames {
            #expect(frame.width > 0 && frame.height > 0)
            #expect(area.insetBy(dx: -epsilon, dy: -epsilon).contains(frame))
        }
        // Neighbours keep at least the gap between them.
        for i in frames.indices {
            for j in frames.indices where j > i {
                let a = frames[i].insetBy(dx: gap / 2 - epsilon, dy: gap / 2 - epsilon)
                let b = frames[j].insetBy(dx: gap / 2 - epsilon, dy: gap / 2 - epsilon)
                #expect(!a.intersects(b), "\(layout) \(count): \(frames[i]) and \(frames[j]) overlap")
            }
        }
    }

    @Test(arguments: Layout.allCases)
    func areaIsFilled(layout: Layout) {
        // With no gap, frames cover the whole area.
        let area = layout == .centeredMaster ? ultrawide : landscape
        for count in 1...9 {
            let covered = layout.frames(count: count, in: area, gap: 0).reduce(0) { $0 + $1.width * $1.height }
            #expect(abs(covered - area.width * area.height) < 1, "\(layout) \(count)")
        }
    }

    @Test func noWindowsNoFrames() {
        #expect(Layout.balancedGrid.frames(count: 0, in: landscape, gap: gap).isEmpty)
    }
}

struct LayoutShapeTests {
    @Test func balancedGridOnLandscape() {
        let two = Layout.balancedGrid.frames(count: 2, in: landscape, gap: 0)
        #expect(two[0].minY == two[1].minY)  // Side by side.
        let three = Layout.balancedGrid.frames(count: 3, in: landscape, gap: 0)
        #expect(three[0].width == 800 && three[2].width == 1600)  // Two on top, one wide below.
        let four = Layout.balancedGrid.frames(count: 4, in: landscape, gap: 0)
        #expect(four.allSatisfy { $0.width == 800 && $0.height == 450 })
    }

    @Test func balancedGridOnPortraitStacks() {
        let two = Layout.balancedGrid.frames(count: 2, in: portrait, gap: 0)
        #expect(two[0].minX == two[1].minX)
    }

    @Test func masterStack() {
        let frames = Layout.masterStack.frames(count: 3, in: landscape, gap: gap)
        #expect(frames[0].width == ((1600 - gap) * 0.6).rounded())
        #expect(frames[0].height == 900)
        #expect(frames[1].minX == frames[2].minX && frames[1].maxY < frames[2].minY)
    }

    @Test func centeredMaster() {
        let two = Layout.centeredMaster.frames(count: 2, in: ultrawide, gap: 0)
        #expect(two[0].minX == 0 && two[1].maxX == 3440)  // No left stack: master takes its room.
        let four = Layout.centeredMaster.frames(count: 4, in: ultrawide, gap: 0)
        #expect(four[0].minX == 860 && four[0].width == 1720)
        #expect(four[1].minX == 2580 && four[2].minX == 0 && four[3].minX == 2580)
    }

    @Test func centeredMasterOnlyOnUltrawide() {
        #expect(!Layout.available(for: landscape).contains(.centeredMaster))
        #expect(Layout.available(for: ultrawide).last == .centeredMaster)
        #expect(Layout.available(for: landscape).first == .balancedGrid)
    }
}

struct ArrangeHistoryTests {
    let available: [Layout] = [.balancedGrid, .masterStack, .columns]
    let start = Date(timeIntervalSinceReferenceDate: 0)

    private func press(
        _ history: inout ArrangeHistory<Int>, step: Int = 1, after seconds: TimeInterval, windows: Set<Int> = [1, 2],
        display: String = "D"
    ) -> Layout {
        history.layout(
            display: display, windows: windows, available: available, step: step,
            now: start.addingTimeInterval(seconds), timeout: 3)
    }

    @Test func repeatedPressesCycleAndWrap() {
        var history = ArrangeHistory<Int>()
        #expect(press(&history, after: 0) == .balancedGrid)
        #expect(press(&history, after: 1) == .masterStack)
        #expect(press(&history, after: 2) == .columns)
        #expect(press(&history, after: 3) == .balancedGrid)
        #expect(press(&history, step: -1, after: 4) == .columns)
    }

    @Test func laterPressReusesTheRememberedLayout() {
        var history = ArrangeHistory<Int>()
        _ = press(&history, after: 0)
        _ = press(&history, after: 1)
        #expect(press(&history, after: 60) == .masterStack)
        #expect(history.rememberedLayout(for: "D") == .masterStack)
    }

    @Test func newWindowSetOrDisplayStartsOver() {
        var history = ArrangeHistory<Int>()
        _ = press(&history, after: 0)
        #expect(press(&history, after: 1, windows: [1, 2, 3]) == .balancedGrid)
        #expect(press(&history, after: 1.5, windows: [1, 2, 3], display: "E") == .balancedGrid)
    }

    @Test func previousOutsideACycleStepsBackFromTheRememberedLayout() {
        var history = ArrangeHistory<Int>()
        #expect(press(&history, step: -1, after: 0) == .columns)
    }
}
