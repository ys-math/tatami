import Foundation

/// User settings stored in `~/.config/tatami/config.json`.
///
/// Every field is optional in the file; missing fields take their defaults.
/// A binding set to `null` is disabled; a missing binding uses the default.
public struct Config: Sendable, Equatable {
    public var defaultGrid: GridSize = .default
    public var outerGap: Double = 8
    public var innerGap: Double = 8
    /// Resizes never make a window smaller than this.
    public var minimumWindowSize = Size(width: 100, height: 60)
    /// Points a boundary moves per `HJKL` press in boundary mode.
    public var fineStep: Double = 10
    /// Resolved bindings: only enabled actions are present.
    public var bindings: [Action: Hotkey]

    public var gaps: Gaps { Gaps(outer: outerGap, inner: innerGap) }

    public static let `default` = Config()

    public struct Size: Codable, Sendable, Equatable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }

        public var cgSize: CGSize { CGSize(width: width, height: height) }
    }

    public init() {
        bindings = Action.defaultBindings.mapValues { try! Hotkey(parsing: $0) }
    }
}

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case invalidJSON(String)
    case unknownAction(String)
    case invalidHotkey(action: String, Hotkey.ParseError)
    case duplicateHotkey(String, [String])
    case invalidValue(String)

    public var description: String {
        switch self {
        case .invalidJSON(let detail): "invalid JSON: \(detail)"
        case .unknownAction(let name): "unknown action '\(name)'"
        case .invalidHotkey(let action, let error): "\(action): \(error)"
        case .duplicateHotkey(let hotkey, let actions): "\(hotkey) is bound to \(actions.joined(separator: ", "))"
        case .invalidValue(let detail): detail
        }
    }
}

extension Config {
    /// On-disk shape; all fields optional.
    private struct File: Codable {
        var defaultGrid: GridSize?
        var outerGap: Double?
        var innerGap: Double?
        var minimumWindowSize: Size?
        var fineStep: Double?
        var bindings: [String: String?]?
    }

    public static func decode(from data: Data) throws(ConfigError) -> Config {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw .invalidJSON(Self.describe(error))
        }

        var config = Config()
        if let grid = file.defaultGrid { config.defaultGrid = grid }
        if let outer = file.outerGap { config.outerGap = outer }
        if let inner = file.innerGap { config.innerGap = inner }
        guard config.outerGap >= 0, config.innerGap >= 0 else { throw .invalidValue("gaps must not be negative") }
        if let size = file.minimumWindowSize { config.minimumWindowSize = size }
        if let step = file.fineStep { config.fineStep = step }
        guard config.fineStep > 0 else { throw .invalidValue("fineStep must be positive") }
        guard config.minimumWindowSize.width >= 0, config.minimumWindowSize.height >= 0 else {
            throw .invalidValue("minimumWindowSize must not be negative")
        }

        for (name, value) in file.bindings ?? [:] {
            guard let action = Action(rawValue: name) else { throw .unknownAction(name) }
            guard let value else {
                config.bindings[action] = nil
                continue
            }
            do {
                config.bindings[action] = try Hotkey(parsing: value)
            } catch {
                throw .invalidHotkey(action: name, error)
            }
        }

        let byHotkey = Dictionary(grouping: config.bindings, by: \.value)
        if let (hotkey, pairs) = byHotkey.first(where: { $0.value.count > 1 }) {
            throw .duplicateHotkey(hotkey.description, pairs.map(\.key.rawValue).sorted())
        }
        return config
    }

    /// The full default configuration as pretty JSON, written on first launch.
    public static func defaultFileContents() -> Data {
        let file = File(
            defaultGrid: Config.default.defaultGrid,
            outerGap: Config.default.outerGap,
            innerGap: Config.default.innerGap,
            minimumWindowSize: Config.default.minimumWindowSize,
            fineStep: Config.default.fineStep,
            // Unbound actions are listed as null so they are easy to discover.
            bindings: Dictionary(
                uniqueKeysWithValues: Action.allCases.map { ($0.rawValue, Action.defaultBindings[$0]) }))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try! encoder.encode(file)
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context),
            DecodingError.typeMismatch(_, let context),
            DecodingError.valueNotFound(_, let context),
            DecodingError.keyNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            let detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return [path.isEmpty ? nil : path, detail ?? context.debugDescription].compactMap { $0 }
                .joined(separator: ": ")
        default:
            return error.localizedDescription
        }
    }
}
