/// A key combination parsed from a string such as `"ctrl+alt+shift+h"`.
///
/// Key codes are macOS virtual key codes (ANSI layout positions), so bindings
/// refer to physical keys.
public struct Hotkey: Sendable, Hashable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case empty
        case unknownToken(String)
        case missingKey
        case multipleKeys

        public var description: String {
            switch self {
            case .empty: "empty hotkey"
            case .unknownToken(let token): "unknown key or modifier '\(token)'"
            case .missingKey: "no key, only modifiers"
            case .multipleKeys: "more than one non-modifier key"
            }
        }
    }

    public var keyCode: Int
    public var modifiers: Modifiers

    public init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(parsing string: String) throws(ParseError) {
        let tokens = string.lowercased().split(separator: "+", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !tokens.isEmpty else { throw .empty }

        var modifiers: Modifiers = []
        var keyCode: Int?
        for token in tokens {
            if let modifier = Self.modifierNames[token] {
                modifiers.insert(modifier)
            } else if let code = Self.keyCodes[token] {
                guard keyCode == nil else { throw .multipleKeys }
                keyCode = code
            } else {
                throw .unknownToken(token)
            }
        }
        guard let keyCode else { throw .missingKey }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    /// Canonical string form, e.g. `ctrl+alt+shift+h`.
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(Self.keyNames[keyCode] ?? "key\(keyCode)")
        return parts.joined(separator: "+")
    }

    private static let modifierNames: [String: Modifiers] = [
        "ctrl": .control, "control": .control,
        "alt": .option, "opt": .option, "option": .option,
        "shift": .shift,
        "cmd": .command, "command": .command,
    ]

    /// Canonical key names; the first name for a code is used by `description`.
    private static let keyTable: [(String, Int)] = [
        ("a", 0x00), ("s", 0x01), ("d", 0x02), ("f", 0x03), ("h", 0x04), ("g", 0x05), ("z", 0x06),
        ("x", 0x07), ("c", 0x08), ("v", 0x09), ("b", 0x0B), ("q", 0x0C), ("w", 0x0D), ("e", 0x0E),
        ("r", 0x0F), ("y", 0x10), ("t", 0x11), ("1", 0x12), ("2", 0x13), ("3", 0x14), ("4", 0x15),
        ("6", 0x16), ("5", 0x17), ("=", 0x18), ("9", 0x19), ("7", 0x1A), ("-", 0x1B), ("8", 0x1C),
        ("0", 0x1D), ("]", 0x1E), ("o", 0x1F), ("u", 0x20), ("[", 0x21), ("i", 0x22), ("p", 0x23),
        ("return", 0x24), ("l", 0x25), ("j", 0x26), ("'", 0x27), ("k", 0x28), (";", 0x29), ("\\", 0x2A),
        (",", 0x2B), ("/", 0x2C), ("n", 0x2D), ("m", 0x2E), (".", 0x2F), ("tab", 0x30), ("space", 0x31),
        ("`", 0x32), ("delete", 0x33), ("escape", 0x35),
        ("f1", 0x7A), ("f2", 0x78), ("f3", 0x63), ("f4", 0x76), ("f5", 0x60), ("f6", 0x61),
        ("f7", 0x62), ("f8", 0x64), ("f9", 0x65), ("f10", 0x6D), ("f11", 0x67), ("f12", 0x6F),
        ("left", 0x7B), ("right", 0x7C), ("down", 0x7D), ("up", 0x7E),
    ]

    private static let aliases: [String: String] = [
        "enter": "return", "esc": "escape", "backspace": "delete",
        "minus": "-", "equal": "=", "comma": ",", "period": ".", "slash": "/",
        "semicolon": ";", "quote": "'", "backslash": "\\", "grave": "`",
        "leftbracket": "[", "rightbracket": "]",
    ]

    private static let keyNames: [Int: String] = Dictionary(
        keyTable.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

    private static let keyCodes: [String: Int] = {
        var codes = Dictionary(uniqueKeysWithValues: keyTable)
        for (alias, name) in aliases {
            codes[alias] = codes[name]
        }
        return codes
    }()
}
