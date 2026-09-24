import CoreGraphics
import Testing

@testable import TatamiCore

/// Uses the gapped 4x2 grid: cells 250x250 with 10pt gaps.
private func cells(_ column: Int, _ row: Int, _ columns: Int, _ rows: Int) -> CGRect {
    gappedGrid.rect(for: CellSpan(column: column, row: row, columnCount: columns, rowCount: rows))
}

private let quarters = [
    "TL": cells(0, 0, 2, 1), "TR": cells(2, 0, 2, 1), "BL": cells(0, 1, 2, 1), "BR": cells(2, 1, 2, 1),
]
/// A | (B / C)
private let tJunction = ["A": cells(0, 0, 2, 2), "B": cells(2, 0, 2, 1), "C": cells(2, 1, 2, 1)]

struct NeighborTests {
    @Test func findsTheWindowInEachDirection() {
        #expect(Swaps.neighbor(of: "TL", .right, frames: quarters) == "TR")
        #expect(Swaps.neighbor(of: "TL", .down, frames: quarters) == "BL")
        #expect(Swaps.neighbor(of: "BR", .left, frames: quarters) == "BL")
        #expect(Swaps.neighbor(of: "BR", .up, frames: quarters) == "TR")
        #expect(Swaps.neighbor(of: "TL", .left, frames: quarters) == nil)
    }

    @Test func diagonalWindowsAreNotNeighbours() {
        #expect(Swaps.neighbor(of: "TL", .right, frames: ["TL": quarters["TL"]!, "BR": quarters["BR"]!]) == nil)
    }

    @Test func prefersTheLongestSharedEdge() {
        // When A faces two windows, the one sharing more of A's edge wins.
        #expect(Swaps.neighbor(of: "B", .left, frames: tJunction) == "A")
        let skewed = [
            "A": cells(0, 0, 2, 2), "B": CGRect(x: 620, y: 50, width: 510, height: 400), "C": cells(2, 1, 2, 1),
        ]
        #expect(Swaps.neighbor(of: "A", .right, frames: skewed) == "B")
    }
}

struct SwapRotateTests {
    @Test func swapExchangesFrames() {
        let result = Swaps.swap("A", "B", frames: tJunction)
        #expect(result == ["A": tJunction["B"]!, "B": tJunction["A"]!])
        #expect(Swaps.swap("A", "A", frames: tJunction) == nil)
    }

    @Test func clockwiseOrderGoesAroundTheScreen() {
        #expect(Swaps.clockwiseOrder(quarters) == ["TL", "TR", "BR", "BL"])
        #expect(Swaps.clockwiseOrder(tJunction) == ["A", "B", "C"])
    }

    @Test func rotateMovesEveryWindowOneSlot() {
        let clockwise = Swaps.rotate(quarters, clockwise: true)
        #expect(clockwise?["TL"] == quarters["TR"])  // The top-left window moves right.
        #expect(clockwise?["TR"] == quarters["BR"])
        #expect(clockwise?["BR"] == quarters["BL"])
        #expect(clockwise?["BL"] == quarters["TL"])
        let back = Swaps.rotate(quarters, clockwise: false)
        #expect(back?["TR"] == quarters["TL"])
    }

    @Test func rotateKeepsTheSetOfSlots() {
        let rotated = Swaps.rotate(tJunction, clockwise: true)!
        #expect(Set(rotated.values) == Set(tJunction.values))
        #expect(rotated["A"] == tJunction["B"] && rotated["C"] == tJunction["A"])
    }

    @Test func nothingToRotateWithOneWindow() {
        #expect(Swaps.rotate(["A": cells(0, 0, 1, 1)], clockwise: true) == nil)
    }

    @Test func mainPartnerIsTheLargestOrTheNextLargest() {
        let order = ["B", "C", "A"]
        #expect(Swaps.mainPartner(of: "B", frames: tJunction, order: order) == "A")
        // A is already main: swap with the frontmost of the equally large others.
        #expect(Swaps.mainPartner(of: "A", frames: tJunction, order: order) == "B")
        #expect(Swaps.mainPartner(of: "A", frames: ["A": tJunction["A"]!], order: ["A"]) == nil)
    }
}
