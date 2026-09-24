import AppKit
import TatamiCore

/// The `⌃⌥ w` window mode, like vim's `<C-w>` but staying open until Escape:
/// labels on the focused display's windows, `hjkl` swap, `r`/`R` rotate (the
/// selected windows if two or more are selected, otherwise all), `m` swap
/// with main.
@MainActor
final class WindowModeController<System: WindowSystem> {
    private let executor: CommandExecutor<System>
    private var session: Session?
    private var panel: OverlayPanel?

    private struct Session {
        var display: Display
        var focused: System.Window
        var state: WindowModeState<System.Window>
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
            let display = Display.containing(frame, in: system.displays()),
            let state = WindowModeState(frames: executor.swappableFrames(on: display, focused: window))
        else {
            NSSound.beep()
            return
        }
        session = Session(display: display, focused: window, state: state)
        show()
    }

    func end() {
        session = nil
        panel?.orderOut(nil)
    }

    private func handle(_ input: WindowModeInput) {
        guard var session else { return }
        let effect = session.state.handle(input)

        switch effect {
        case .updated:
            self.session = session
            show()
        case .ignored:
            self.session = session
            NSSound.beep()
        case .action(let action):
            if !executor.execute(action) {
                NSSound.beep()
            }
            refresh(&session)
        case .rotateGroup(let group, let clockwise):
            if !executor.rotate(group: group, clockwise: clockwise) {
                NSSound.beep()
            }
            refresh(&session)
        case .exit:
            end()
        }
    }

    /// Re-reads the windows' frames after a command and redraws.
    private func refresh(_ session: inout Session) {
        var frames: [System.Window: CGRect] = [:]
        for window in session.state.windows {
            frames[window] = executor.system.frame(of: window)
        }
        session.state.refresh(frames: frames)
        self.session = session
        show()
    }

    private func show() {
        guard let session, let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let display = session.display
        let panel = self.panel ?? makePanel()
        self.panel = panel

        panel.setFrame(Coordinates.flip(display.frame, primaryHeight: primaryHeight), display: false)
        let view = WindowModeView(frame: NSRect(origin: .zero, size: display.frame.size))
        let state = session.state
        view.model = WindowModeView.Model(
            windows: state.windows.compactMap { window in
                state.frames[window].map { frame in
                    WindowModeView.Window(
                        frame: frame, label: state.label(of: window) ?? "",
                        selected: state.selected.contains(window), focused: window == session.focused,
                        dimmed: !state.typed.isEmpty && !(state.label(of: window) ?? "").hasPrefix(state.typed))
                }
            },
            selectedCount: state.selected.count, origin: display.frame.origin)
        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel()
        panel.onKeyDown = { [weak self] event in
            if let input = WindowModeKeys.input(for: event) {
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

/// Decodes key events for window mode: commands by physical key code,
/// labels by the typed character.
enum WindowModeKeys {
    static func input(for event: NSEvent) -> WindowModeInput? {
        input(
            keyCode: Int(event.keyCode), characters: event.charactersIgnoringModifiers ?? "",
            shift: event.modifierFlags.contains(.shift))
    }

    static func input(keyCode: Int, characters: String, shift: Bool) -> WindowModeInput? {
        switch keyCode {
        case 0x04: return .swap(.left)  // h
        case 0x26: return .swap(.down)  // j
        case 0x28: return .swap(.up)  // k
        case 0x25: return .swap(.right)  // l
        case 0x0F: return .rotate(clockwise: !shift)  // r / R
        case 0x2E: return .swapWithMain  // m
        case 0x35: return .exit  // Escape
        default: break
        }
        guard characters.count == 1, let character = characters.lowercased().first,
            character.isLetter || character.isNumber
        else { return nil }
        return .character(character)
    }
}
