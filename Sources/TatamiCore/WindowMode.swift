import CoreGraphics

public enum WindowModeInput: Equatable, Sendable {
    /// A label character: toggles that window's selection.
    case character(Character)
    /// `hjkl`: swap the focused window with its neighbour.
    case swap(Direction)
    /// `r` / `R`.
    case rotate(clockwise: Bool)
    /// `m`.
    case swapWithMain
    /// Escape.
    case exit
}

public enum WindowModeEffect<ID: Hashable>: Equatable {
    case updated
    case ignored
    /// Run a focused-window action (swap in a direction, rotate all, swap with main).
    case action(Action)
    /// Rotate just these windows one slot (two windows: swap).
    case rotateGroup(Set<ID>, clockwise: Bool)
    case exit
}

/// The `⌃⌥ w` window mode: labels on the display's windows, a selection
/// toggled by label, and commands that move windows between slots. Stays
/// open until Escape. Pure; the app runs the effects and calls `refresh`.
public struct WindowModeState<ID: Hashable> {
    /// Keys taken by commands, so never used in labels.
    public static var reservedKeys: Set<Character> { ["h", "j", "k", "l", "r", "m"] }

    /// Windows in label order (reading order when the mode began). Labels
    /// stay with their window as it moves.
    public private(set) var windows: [ID]
    public private(set) var frames: [ID: CGRect]
    public private(set) var selected: Set<ID> = []
    public private(set) var typed = ""
    public let labels: [String]

    /// Returns `nil` when there are no windows.
    public init?(frames: [ID: CGRect]) {
        guard !frames.isEmpty else { return nil }
        self.frames = frames
        windows = frames.keys.sorted { a, b in
            let fa = frames[a]!
            let fb = frames[b]!
            return (fa.minY, fa.minX) < (fb.minY, fb.minX)
        }
        labels = GridLabels.sequence(count: frames.count, excluding: Self.reservedKeys)
    }

    public func label(of window: ID) -> String? {
        windows.firstIndex(of: window).map { labels[$0] }
    }

    public mutating func handle(_ input: WindowModeInput) -> WindowModeEffect<ID> {
        switch input {
        case .character(let character):
            return type(character)
        case .swap(let direction):
            typed = ""
            switch direction {
            case .left: return .action(.swapLeft)
            case .down: return .action(.swapDown)
            case .up: return .action(.swapUp)
            case .right: return .action(.swapRight)
            }
        case .rotate(let clockwise):
            typed = ""
            switch selected.count {
            case 0: return .action(clockwise ? .rotateClockwise : .rotateCounterclockwise)
            case 1: return .ignored
            default: return .rotateGroup(selected, clockwise: clockwise)
            }
        case .swapWithMain:
            typed = ""
            return .action(.swapWithMain)
        case .exit:
            return .exit
        }
    }

    /// Takes the windows' real frames after a command; windows that are gone
    /// are dropped from the selection.
    public mutating func refresh(frames: [ID: CGRect]) {
        self.frames = frames.filter { windows.contains($0.key) }
        selected = selected.filter { self.frames[$0] != nil }
    }

    private mutating func type(_ character: Character) -> WindowModeEffect<ID> {
        let candidate = typed + String(character).lowercased()
        if let index = labels.firstIndex(of: candidate) {
            typed = ""
            let window = windows[index]
            guard frames[window] != nil else { return .ignored }
            if selected.contains(window) {
                selected.remove(window)
            } else {
                selected.insert(window)
            }
            return .updated
        }
        guard labels.contains(where: { $0.hasPrefix(candidate) }) else {
            typed = ""
            return .ignored
        }
        typed = candidate
        return .updated
    }
}
