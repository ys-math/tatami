import CoreGraphics
import Testing

@testable import TatamiCore

/// 4x4 grid over the gapped area: columns 100–350, 360–610, 620–870, 880–1130
/// (lines at x = 355, 615, 875); rows of 120pt (lines at y = 175, 305, 435).
private let grid = Grid(size: GridSize(columns: 4, rows: 4), area: gappedGrid.area, innerGap: 10)

private func cells(_ column: Int, _ row: Int, _ columns: Int, _ rows: Int) -> CGRect {
    grid.rect(for: CellSpan(column: column, row: row, columnCount: columns, rowCount: rows))
}

/// A | (B / C)
private let tJunction = ["A": cells(0, 0, 2, 4), "B": cells(2, 0, 2, 2), "C": cells(2, 2, 2, 2)]
/// Four quarters.
private let quarters = [
    "TL": cells(0, 0, 2, 2), "TR": cells(2, 0, 2, 2), "BL": cells(0, 2, 2, 2), "BR": cells(2, 2, 2, 2),
]

private func makeState(_ frames: [String: CGRect], focused: String? = nil) -> BoundaryModeState<String>? {
    BoundaryModeState(
        frames: frames, focused: focused, grid: grid, minimumSize: CGSize(width: 50, height: 50), fineStep: 10)
}

struct BoundaryEnumerationTests {
    @Test func twoHalvesHaveOneBoundary() {
        let found = Boundaries.all(frames: ["A": cells(0, 0, 2, 4), "B": cells(2, 0, 2, 4)], grid: grid)
        #expect(found.boundaries.count == 1)
        #expect(found.boundaries.first?.position == 615)
        #expect(found.crosspoints.isEmpty)
    }

    @Test func tJunctionHasTwoBoundariesAndACrosspoint() throws {
        let found = Boundaries.all(frames: tJunction, grid: grid)
        #expect(found.boundaries.count == 2)
        let vertical = try #require(found.boundaries.first { $0.axis == .horizontal })
        #expect(vertical.before == ["A"] && vertical.after == ["B", "C"])
        let horizontal = try #require(found.boundaries.first { $0.axis == .vertical })
        #expect(horizontal.before == ["B"] && horizontal.after == ["C"])
        #expect(found.crosspoints.map(\.point) == [CGPoint(x: 615, y: 305)])
    }

    @Test func quartersSplitIntoMinimalSegmentsMeetingAtOneDot() throws {
        let found = Boundaries.all(frames: quarters, grid: grid)
        #expect(found.boundaries.count == 4)
        #expect(found.boundaries.allSatisfy { $0.members.count == 2 })
        let dot = try #require(found.crosspoints.first)
        #expect(found.crosspoints.count == 1)
        #expect(dot.point == CGPoint(x: 615, y: 305))
        #expect(dot.verticals.count == 2 && dot.horizontals.count == 2)
        // The dot still moves whole lines.
        #expect(dot.vertical.members == ["TL", "TR", "BL", "BR"])
    }

    @Test func tJunctionVerticalCannotBeSplit() throws {
        // A's whole right edge faces both B and C, so they stay one boundary.
        let vertical = try #require(
            Boundaries.all(frames: tJunction, grid: grid).boundaries.first { $0.axis == .horizontal })
        #expect(vertical.after == ["B", "C"])
    }

    @Test func staggeredLayoutKeepsTheConnectedLineWhole() {
        // Quarters after moving only the top segment right to x = 875.
        var staggered = quarters
        staggered["TL"] = cells(0, 0, 3, 2)
        staggered["TR"] = cells(3, 0, 1, 2)
        let found = Boundaries.all(frames: staggered, grid: grid)
        let verticals = found.boundaries.filter { $0.axis == .horizontal }
        #expect(Set(verticals.map(\.position)) == [615, 875])
        // TL faces BL and BR across the horizontal line, TR faces BR: one boundary.
        let horizontals = found.boundaries.filter { $0.axis == .vertical }
        #expect(horizontals.count == 1)
        #expect(horizontals.first?.members.count == 4)
    }

    @Test func labelsStayOffCrosspoints() throws {
        let found = Boundaries.all(frames: tJunction, grid: grid)
        let vertical = try #require(found.boundaries.first { $0.axis == .horizontal })
        let label = Boundaries.labelPoint(for: vertical, junctions: found.crosspoints.map(\.point))
        // The line runs y 50–560 with the T at 305: the label sits mid-way along one half.
        #expect(label == CGPoint(x: 615, y: 177.5))
    }

    @Test func separateWindowsHaveNoBoundaries() {
        let found = Boundaries.all(frames: ["A": cells(0, 0, 1, 1), "B": cells(2, 2, 1, 1)], grid: grid)
        #expect(found.boundaries.isEmpty && found.crosspoints.isEmpty)
    }
}

struct BoundaryModeStateTests {
    @Test func noJoinedWindowsMeansNoMode() {
        #expect(makeState(["A": cells(0, 0, 1, 1)]) == nil)
    }

    @Test func startsOnTheFocusedWindowsNearestBoundary() throws {
        let fromC = try #require(makeState(tJunction, focused: "C"))
        // C touches both lines; the horizontal line (y = 305, moving along the vertical axis) is nearer its center.
        guard case .boundary(let boundary) = fromC.selected else {
            Issue.record("expected a boundary")
            return
        }
        #expect(boundary.axis == .vertical)

        let fromA = try #require(makeState(tJunction, focused: "A"))
        guard case .boundary(let aBoundary) = fromA.selected else {
            Issue.record("expected a boundary")
            return
        }
        #expect(aBoundary.axis == .horizontal)
    }

    @Test func hjklMovesTheSelectedLineToTheNextGridLine() throws {
        var state = try #require(makeState(tJunction, focused: "A"))
        guard case .apply(let targets) = state.handle(.move(.right)) else {
            Issue.record("expected apply")
            return
        }
        #expect(targets["A"]?.maxX == 870)
        #expect(targets["B"]?.minX == 880 && targets["C"]?.minX == 880)
        // The selection follows the moved line.
        guard case .boundary(let boundary) = state.selected else {
            Issue.record("expected a boundary")
            return
        }
        #expect(boundary.position == 875)
    }

    @Test func verticalLineIgnoresUpAndDown() throws {
        var state = try #require(makeState(tJunction, focused: "A"))
        #expect(state.handle(.move(.up)) == .ignored)
        #expect(state.handle(.fineMove(.down)) == .ignored)
    }

    @Test func fineStepMovesByPoints() throws {
        var state = try #require(makeState(tJunction, focused: "A"))
        guard case .apply(let targets) = state.handle(.fineMove(.left)) else {
            Issue.record("expected apply")
            return
        }
        #expect(targets["A"]?.maxX == 600)
        #expect(targets["B"]?.minX == 610)
    }

    @Test func crosspointMovesAlongBothAxes() throws {
        var state = try #require(makeState(quarters))
        let index = try #require(state.items.firstIndex { $0.isCrosspoint })
        #expect(state.handle(.character(Character(state.labels[index]))) == .updated)
        #expect(state.selected.isCrosspoint)

        guard case .apply(let horizontalMove) = state.handle(.move(.left)) else {
            Issue.record("expected apply")
            return
        }
        #expect(horizontalMove.count == 4)
        #expect(horizontalMove["TL"]?.maxX == 350 && horizontalMove["BR"]?.minX == 360)

        guard case .apply(let verticalMove) = state.handle(.move(.down)) else {
            Issue.record("expected apply")
            return
        }
        #expect(verticalMove["TL"]?.maxY == 430 && verticalMove["BL"]?.minY == 440)
        #expect(state.selected.isCrosspoint)
        #expect(state.anchors[state.selectedIndex] == CGPoint(x: 355, y: 435))
    }

    @Test func aMinimalSegmentMovesOnlyItsOwnWindows() throws {
        var state = try #require(makeState(quarters, focused: "TL"))
        let top = try #require(
            state.items.firstIndex {
                if case .boundary(let b) = $0 { b.axis == .horizontal && b.members == ["TL", "TR"] } else { false }
            })
        _ = state.handle(.character(Character(state.labels[top])))
        guard case .apply(let targets) = state.handle(.move(.right)) else {
            Issue.record("expected apply")
            return
        }
        #expect(Set(targets.keys) == ["TL", "TR"])
        #expect(targets["TL"]?.maxX == 870 && targets["TR"]?.minX == 880)
    }

    @Test func anchorsNeverOverlap() throws {
        let state = try #require(makeState(tJunction, focused: "A"))
        #expect(Set(state.anchors.map { "\($0.x),\($0.y)" }).count == state.anchors.count)
    }

    @Test func tabCyclesAndLabelsSelect() throws {
        var state = try #require(makeState(tJunction, focused: "A"))
        #expect(state.items.count == 3)
        let start = state.selectedIndex
        _ = state.handle(.next)
        #expect(state.selectedIndex == (start + 1) % 3)
        _ = state.handle(.previous)
        _ = state.handle(.previous)
        #expect(state.selectedIndex == (start + 2) % 3)
        #expect(state.handle(.character(Character(state.labels[1]))) == .updated)
        #expect(state.selectedIndex == 1)
        #expect(state.handle(.character("z")) == .ignored)
    }

    @Test func minimumSizeStopsTheMove() throws {
        var state = try #require(makeState(["A": cells(0, 0, 1, 4), "B": cells(1, 0, 3, 4)], focused: "A"))
        // Moving left would give A zero width.
        #expect(state.handle(.move(.left)) == .ignored)
        #expect(state.handle(.fineMove(.left)) != .ignored)  // 250 → 240 wide is fine
    }

    @Test func refreshKeepsTheSelectionAfterAnAppRefused() throws {
        var state = try #require(makeState(tJunction, focused: "A"))
        _ = state.handle(.move(.right))
        state.refresh(frames: tJunction)  // The move was reverted.
        guard case .boundary(let boundary) = state.selected else {
            Issue.record("expected a boundary")
            return
        }
        #expect(boundary.axis == .horizontal && boundary.position == 615)
        #expect(state.frames == tJunction)
    }

    @Test func exit() throws {
        var state = try #require(makeState(tJunction))
        #expect(state.handle(.exit) == .exit)
    }
}
