import AppKit
import TatamiCore

/// Briefly shows a display's grid after its size changes, or a short label.
@MainActor
final class GridFlash {
    private var panel: NSPanel?
    private var generation = 0

    func show(_ grid: Grid, on display: Display) {
        show(label: "\(grid.size.columns) × \(grid.size.rows)", cells: grid.cellRects(), on: display)
    }

    /// Shows just a label, e.g. the name of the layout auto-arrange used.
    func show(label: String, on display: Display) {
        show(label: label, cells: [], on: display)
    }

    private func show(label: String, cells: [CGRect], on display: Display) {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        panel.setFrame(Coordinates.flip(display.frame, primaryHeight: primaryHeight), display: false)
        let view = GridFlashView(frame: NSRect(origin: .zero, size: display.frame.size))
        view.cells = cells.map { $0.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY) }
        view.label = label
        panel.contentView = view
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        generation += 1
        let current = generation
        Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, let panel, self.generation == current else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }
            if self.generation == current {
                panel.orderOut(nil)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

/// Draws cells in AX-style coordinates (top-left origin).
private final class GridFlashView: NSView {
    var cells: [CGRect] = []
    var label = ""

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for cell in cells {
            let path = NSBezierPath(roundedRect: cell, xRadius: 8, yRadius: 8)
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
            path.lineWidth = 2
            path.stroke()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let size = text.size()
        let box = CGRect(
            x: bounds.midX - size.width / 2 - 24, y: bounds.midY - size.height / 2 - 12,
            width: size.width + 48, height: size.height + 24)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14).fill()
        text.draw(at: CGPoint(x: box.minX + 24, y: box.minY + 12))
    }
}
