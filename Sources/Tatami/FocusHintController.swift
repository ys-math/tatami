import AppKit
import TatamiCore

/// The `⌃⌥ f` hint mode: a label on every window on every display; typing a
/// label focuses that window. Escape, a click or an unknown label cancels.
@MainActor
final class FocusHintController<System: WindowSystem> {
    private let executor: CommandExecutor<System>
    private var state: FocusHintState<System.Window>?
    private var displays: [Display] = []
    /// One overlay per display; the first shown on the focused display takes the keys.
    private var panels: [OverlayPanel] = []

    init(executor: CommandExecutor<System>) {
        self.executor = executor
    }

    var isActive: Bool { state != nil }

    func begin() {
        guard state == nil else {
            end()
            return
        }
        let system = executor.system
        displays = system.displays()
        guard let state = FocusHintState(frames: executor.allFrames(), displays: displays) else {
            NSSound.beep()
            return
        }
        self.state = state
        show()
    }

    func end() {
        state = nil
        for panel in panels {
            panel.orderOut(nil)
        }
    }

    private func type(_ character: Character) {
        guard var state else { return }
        let effect = state.type(character)
        self.state = state
        switch effect {
        case .updated:
            show()
        case .ignored:
            NSSound.beep()
            end()
        case .focus(let window):
            end()
            executor.system.focus(window)
        }
    }

    private func show() {
        guard let state, let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        while panels.count < displays.count {
            panels.append(makePanel())
        }

        let system = executor.system
        let focusedDisplay = system.focusedWindow().flatMap(system.frame(of:)).flatMap {
            Display.containing($0, in: displays)
        }
        var keyPanel: OverlayPanel?
        for (display, panel) in zip(displays, panels) {
            panel.setFrame(Coordinates.flip(display.frame, primaryHeight: primaryHeight), display: false)
            let view = FocusHintView(frame: NSRect(origin: .zero, size: display.frame.size))
            view.origin = display.frame.origin
            view.hints = state.windows.indices.compactMap { index in
                let position = state.positions[index]
                guard display.frame.contains(position) else { return nil }
                let label = state.labels[index]
                return FocusHintView.Hint(
                    label: label, position: position,
                    dimmed: !state.typed.isEmpty && !label.hasPrefix(state.typed))
            }
            panel.contentView = view
            panel.orderFrontRegardless()
            if display.id == focusedDisplay?.id || keyPanel == nil {
                keyPanel = panel
            }
        }
        keyPanel?.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel()
        panel.onKeyDown = { [weak self] event in
            guard let self else { return }
            if event.keyCode == 0x35 {  // Escape
                self.end()
            } else if let characters = event.charactersIgnoringModifiers, characters.count == 1,
                let character = characters.lowercased().first, character.isLetter || character.isNumber
            {
                self.type(character)
            } else {
                NSSound.beep()
            }
        }
        panel.onCancel = { [weak self] in
            self?.end()
        }
        return panel
    }
}

/// Draws hint labels over one display, in AX-style (flipped) coordinates.
private final class FocusHintView: NSView {
    struct Hint {
        var label: String
        var position: CGPoint
        var dimmed: Bool
    }

    var hints: [Hint] = []
    /// The display's top-left corner in AX coordinates.
    var origin: CGPoint = .zero

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()
        for hint in hints {
            let text = NSAttributedString(
                string: hint.label.uppercased(),
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 24, weight: .bold),
                    .foregroundColor: NSColor.black.withAlphaComponent(hint.dimmed ? 0.3 : 1),
                ])
            let size = text.size()
            let width = max(size.width + 24, size.height + 12)
            let box = CGRect(
                x: hint.position.x - origin.x - width / 2, y: hint.position.y - origin.y - (size.height + 12) / 2,
                width: width, height: size.height + 12)
            NSColor.systemYellow.withAlphaComponent(hint.dimmed ? 0.4 : 0.95).setFill()
            NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
            text.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
        }
    }
}
