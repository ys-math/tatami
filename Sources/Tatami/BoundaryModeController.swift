import AppKit
import TatamiCore

/// Runs boundary mode: shows the boundaries and crosspoints of the focused
/// window's display and moves the selected one live.
@MainActor
final class BoundaryModeController<System: WindowSystem> {
    private let executor: CommandExecutor<System>
    private var session: Session?
    private var panel: OverlayPanel?

    private struct Session {
        var display: Display
        var state: BoundaryModeState<System.Window>
    }

    init(executor: CommandExecutor<System>) {
        self.executor = executor
    }

    var isActive: Bool { session != nil }

    func begin() {
        guard session == nil else {
            end()
            return
        }
        let system = executor.system
        guard let window = system.focusedWindow(),
            let frame = system.frame(of: window),
            let display = Display.containing(frame, in: system.displays())
        else { return }

        var frames = executor.frames(on: display)
        frames[window] = frame
        let config = executor.config
        guard
            let state = BoundaryModeState(
                frames: frames, focused: window, grid: executor.grid(for: display),
                minimumSize: config.minimumWindowSize.cgSize, fineStep: config.fineStep)
        else {
            // No windows meet on this display.
            NSSound.beep()
            return
        }
        session = Session(display: display, state: state)
        show()
    }

    func end() {
        session = nil
        panel?.orderOut(nil)
    }

    private func handle(_ input: BoundaryModeInput) {
        guard var session else { return }
        let before = session.state.frames
        let effect = session.state.handle(input)

        switch effect {
        case .updated:
            self.session = session
            show()
        case .ignored:
            self.session = session
            NSSound.beep()
        case .apply(let targets):
            if !executor.apply(targets, originals: before) {
                NSSound.beep()
            }
            // Re-read what the windows actually did (terminals size in steps;
            // refused moves were reverted).
            var actual = before
            for window in before.keys {
                actual[window] = executor.system.frame(of: window) ?? before[window]
            }
            session.state.refresh(frames: actual)
            self.session = session
            show()
        case .exit:
            end()
        }
    }

    private func show() {
        guard let session, let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let display = session.display
        let panel = self.panel ?? makePanel()
        self.panel = panel

        panel.setFrame(Coordinates.flip(display.frame, primaryHeight: primaryHeight), display: false)
        let view = BoundaryModeView(frame: NSRect(origin: .zero, size: display.frame.size))
        view.model = BoundaryModeView.Model(
            items: session.state.items, anchors: session.state.anchors, labels: session.state.labels,
            selectedIndex: session.state.selectedIndex,
            typed: session.state.typed, windows: Array(session.state.frames.values), innerGap: executor.config.innerGap,
            origin: display.frame.origin)
        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel()
        panel.onKeyDown = { [weak self] event in
            if let input = BoundaryModeKeys.input(for: event) {
                self?.handle(input)
            } else {
                NSSound.beep()
            }
        }
        panel.onCancel = { [weak self] in
            self?.handle(.exit)
        }
        return panel
    }
}

/// Decodes key events for boundary mode.
enum BoundaryModeKeys {
    static func input(for event: NSEvent) -> BoundaryModeInput? {
        input(
            keyCode: Int(event.keyCode), characters: event.charactersIgnoringModifiers ?? "",
            shift: event.modifierFlags.contains(.shift))
    }

    static func input(keyCode: Int, characters: String, shift: Bool) -> BoundaryModeInput? {
        let directions: [Int: Direction] = [0x04: .left, 0x26: .down, 0x28: .up, 0x25: .right]
        if let direction = directions[keyCode] {
            return shift ? .fineMove(direction) : .move(direction)
        }
        switch keyCode {
        case 0x35, 0x24, 0x4C: return .exit  // Escape, Return, keypad Enter
        case 0x30: return shift ? .previous : .next  // Tab
        default: break
        }
        guard characters.count == 1, let character = characters.lowercased().first,
            character.isLetter || character.isNumber
        else { return nil }
        return .character(character)
    }
}
