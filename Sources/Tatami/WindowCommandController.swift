import AppKit
import TatamiCore

/// The `⌃⌥ w` prefix, like vim's `<C-w>`: shows a small hint and runs the
/// window command picked by the next key. Cancels on Esc, an unknown key, a
/// click elsewhere, or after `timeout`.
@MainActor
final class WindowCommandController<System: WindowSystem> {
    private let executor: CommandExecutor<System>
    private var panel: OverlayPanel?
    private var generation = 0
    let timeout: Duration = .seconds(2)

    init(executor: CommandExecutor<System>) {
        self.executor = executor
    }

    var isActive: Bool { panel?.isVisible ?? false }

    func begin() {
        let system = executor.system
        guard let window = system.focusedWindow(),
            let frame = system.frame(of: window),
            let display = Display.containing(frame, in: system.displays()),
            let primaryHeight = NSScreen.screens.first?.frame.height
        else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let view = WindowCommandHintView()
        let size = view.fittingSize
        let visible = Coordinates.flip(display.visibleFrame, primaryHeight: primaryHeight)
        panel.setFrame(
            NSRect(x: visible.midX - size.width / 2, y: visible.minY + 80, width: size.width, height: size.height),
            display: false)
        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)

        generation += 1
        let current = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.timeout ?? .seconds(2))
            guard let self, self.generation == current else { return }
            self.end()
        }
    }

    func end() {
        generation += 1
        panel?.orderOut(nil)
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel()
        panel.onKeyDown = { [weak self] event in
            guard let self else { return }
            let action = WindowCommandKeys.action(
                keyCode: Int(event.keyCode), shift: event.modifierFlags.contains(.shift))
            self.end()
            if let action {
                if !self.executor.execute(action) {
                    NSSound.beep()
                }
            } else if event.keyCode != 0x35 {  // Escape cancels quietly.
                NSSound.beep()
            }
        }
        panel.onCancel = { [weak self] in
            self?.end()
        }
        return panel
    }
}

/// Keys after the `⌃⌥ w` prefix, read by physical key code.
enum WindowCommandKeys {
    static func action(keyCode: Int, shift: Bool) -> Action? {
        switch keyCode {
        case 0x04: .swapLeft  // h
        case 0x26: .swapDown  // j
        case 0x28: .swapUp  // k
        case 0x25: .swapRight  // l
        case 0x0F: shift ? .rotateCounterclockwise : .rotateClockwise  // r / R
        case 0x2E: .swapWithMain  // m
        default: nil
        }
    }
}

private final class WindowCommandHintView: NSView {
    private let text = NSAttributedString(
        string: "⌃⌥ w   ·   hjkl swap   ·   r / R rotate   ·   m swap with main   ·   esc",
        attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white])

    override var fittingSize: NSSize {
        let size = text.size()
        return NSSize(width: size.width + 40, height: size.height + 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}
