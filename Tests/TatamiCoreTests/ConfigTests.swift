import Foundation
import Testing

@testable import TatamiCore

struct HotkeyTests {
    @Test func parsesModifiersAndKey() throws {
        let hotkey = try Hotkey(parsing: "ctrl+alt+shift+h")
        #expect(hotkey.keyCode == 0x04)
        #expect(hotkey.modifiers == [.control, .option, .shift])
    }

    @Test func isCaseAndOrderInsensitiveWithAliases() throws {
        #expect(try Hotkey(parsing: "H+Shift+Option+Control") == Hotkey(parsing: "ctrl+alt+shift+h"))
        #expect(try Hotkey(parsing: "cmd+enter") == Hotkey(parsing: "command+return"))
        #expect(try Hotkey(parsing: "ctrl+minus") == Hotkey(parsing: "ctrl+-"))
    }

    @Test func descriptionIsCanonical() throws {
        #expect(try Hotkey(parsing: "shift+cmd+ctrl+Enter").description == "ctrl+shift+cmd+return")
    }

    @Test func rejectsInvalidStrings() {
        #expect(throws: Hotkey.ParseError.empty) { try Hotkey(parsing: "") }
        #expect(throws: Hotkey.ParseError.missingKey) { try Hotkey(parsing: "ctrl+alt") }
        #expect(throws: Hotkey.ParseError.multipleKeys) { try Hotkey(parsing: "ctrl+h+j") }
        #expect(throws: Hotkey.ParseError.unknownToken("hyper")) { try Hotkey(parsing: "hyper+h") }
    }

    @Test func allDefaultBindingsParse() throws {
        for string in Action.defaultBindings.values {
            _ = try Hotkey(parsing: string)
        }
    }

    @Test func perEdgeGrowAndShrinkAreUnboundByDefault() {
        let unbound = Set(Action.allCases).subtracting(Action.defaultBindings.keys)
        #expect(
            unbound == [
                .growLeft, .growDown, .growUp, .growRight, .shrinkLeft, .shrinkDown, .shrinkUp, .shrinkRight,
            ])
    }
}

struct ConfigTests {
    private func decode(_ json: String) throws(ConfigError) -> Config {
        try Config.decode(from: Data(json.utf8))
    }

    @Test func emptyObjectGivesDefaults() throws {
        #expect(try decode("{}") == Config.default)
    }

    @Test func defaultFileRoundTrips() throws {
        #expect(try Config.decode(from: Config.defaultFileContents()) == Config.default)
    }

    @Test func defaultFileListsUnboundActionsAsNull() throws {
        let json = try JSONSerialization.jsonObject(with: Config.defaultFileContents()) as? [String: Any]
        let bindings = try #require(json?["bindings"] as? [String: Any])
        #expect(bindings.count == Action.allCases.count)
        #expect(bindings["growLeft"] is NSNull)
        #expect(bindings["resizeAloneLeft"] as? String == "ctrl+alt+cmd+h")
    }

    @Test func unboundActionsCanBeBound() throws {
        let config = try decode(#"{"bindings": {"growLeft": "ctrl+alt+cmd+shift+h"}}"#)
        #expect(config.bindings[.growLeft] == (try Hotkey(parsing: "ctrl+alt+cmd+shift+h")))
    }

    @Test func overridesFieldsAndBindings() throws {
        let config = try decode(
            #"""
            {
              "defaultGrid": { "columns": 6, "rows": 3 },
              "innerGap": 0,
              "bindings": { "maximize": "cmd+alt+m", "center": null }
            }
            """#)
        #expect(config.defaultGrid == GridSize(columns: 6, rows: 3))
        #expect(config.innerGap == 0)
        #expect(config.outerGap == 8)
        #expect(config.bindings[.maximize] == (try Hotkey(parsing: "alt+cmd+m")))
        #expect(config.bindings[.center] == nil)
        #expect(config.bindings[.moveLeft] == (try Hotkey(parsing: "ctrl+alt+h")))
    }

    @Test func reportsErrors() {
        #expect(throws: ConfigError.unknownAction("teleport")) {
            try decode(#"{"bindings": {"teleport": "ctrl+t"}}"#)
        }
        #expect(throws: ConfigError.invalidHotkey(action: "split", .unknownToken("hyper"))) {
            try decode(#"{"bindings": {"split": "hyper+s"}}"#)
        }
        #expect(throws: ConfigError.duplicateHotkey("ctrl+alt+h", ["moveLeft", "split"])) {
            try decode(#"{"bindings": {"split": "ctrl+alt+h"}}"#)
        }
        #expect(throws: ConfigError.invalidValue("gaps must not be negative")) {
            try decode(#"{"outerGap": -1}"#)
        }
        #expect(throws: ConfigError.invalidValue("fineStep must be positive")) {
            try decode(#"{"fineStep": 0}"#)
        }
        #expect(throws: ConfigError.self) { try decode("{ not json") }
        #expect(throws: ConfigError.self) { try decode(#"{"outerGap": "big"}"#) }
    }
}
