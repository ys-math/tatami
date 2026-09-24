import TatamiCore
import Testing

@testable import Tatami

struct GridModeKeysTests {
    @Test func hjklMoveAndShiftResize() {
        #expect(GridModeKeys.input(keyCode: 0x04, characters: "h", shift: false) == .move(.left))
        #expect(GridModeKeys.input(keyCode: 0x26, characters: "J", shift: true) == .resize(.down))
        #expect(GridModeKeys.input(keyCode: 0x28, characters: "k", shift: false) == .move(.up))
        #expect(GridModeKeys.input(keyCode: 0x25, characters: "L", shift: true) == .resize(.right))
    }

    @Test func controlKeys() {
        #expect(GridModeKeys.input(keyCode: 0x35, characters: "\u{1B}", shift: false) == .cancel)
        #expect(GridModeKeys.input(keyCode: 0x24, characters: "\r", shift: false) == .apply)
        #expect(GridModeKeys.input(keyCode: 0x30, characters: "\t", shift: false) == .nextDisplay)
    }

    @Test func gridSizeKeys() {
        #expect(GridModeKeys.input(keyCode: 0x1B, characters: "-", shift: false) == .adjustGrid(columns: -1, rows: 0))
        #expect(GridModeKeys.input(keyCode: 0x18, characters: "=", shift: false) == .adjustGrid(columns: 1, rows: 0))
        #expect(GridModeKeys.input(keyCode: 0x1B, characters: "_", shift: true) == .adjustGrid(columns: 0, rows: -1))
        #expect(GridModeKeys.input(keyCode: 0x18, characters: "+", shift: true) == .adjustGrid(columns: 0, rows: 1))
    }

    @Test func labelsAreLowercasedCharacters() {
        #expect(GridModeKeys.input(keyCode: 0x0C, characters: "Q", shift: true) == .character("q"))
        #expect(GridModeKeys.input(keyCode: 0x12, characters: "1", shift: false) == .character("1"))
        #expect(GridModeKeys.input(keyCode: 0x31, characters: " ", shift: false) == nil)
    }
}

struct BoundaryModeKeysTests {
    @Test func keys() {
        #expect(BoundaryModeKeys.input(keyCode: 0x04, characters: "h", shift: false) == .move(.left))
        #expect(BoundaryModeKeys.input(keyCode: 0x25, characters: "L", shift: true) == .fineMove(.right))
        #expect(BoundaryModeKeys.input(keyCode: 0x30, characters: "\t", shift: false) == .next)
        #expect(BoundaryModeKeys.input(keyCode: 0x30, characters: "\t", shift: true) == .previous)
        #expect(BoundaryModeKeys.input(keyCode: 0x24, characters: "\r", shift: false) == .exit)
        #expect(BoundaryModeKeys.input(keyCode: 0x35, characters: "\u{1B}", shift: false) == .exit)
        #expect(BoundaryModeKeys.input(keyCode: 0x00, characters: "A", shift: true) == .character("a"))
    }
}
