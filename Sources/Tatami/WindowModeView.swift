import AppKit
import TatamiCore

/// Draws window mode for one display, in AX-style (flipped) coordinates.
final class WindowModeView: NSView {
    struct Window {
        var frame: CGRect
        var label: String
        var selected: Bool
        var focused: Bool
        var dimmed: Bool
    }

    struct Model {
        var windows: [Window]
        var selectedCount: Int
        /// The display's top-left corner in AX coordinates.
        var origin: CGPoint
    }

    var model: Model?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        for window in model.windows {
            let rect = window.frame.offsetBy(dx: -model.origin.x, dy: -model.origin.y)
            let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            (window.selected
                ? NSColor.controlAccentColor.withAlphaComponent(0.3) : NSColor.white.withAlphaComponent(0.06))
                .setFill()
            path.fill()
            (window.selected
                ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(window.focused ? 0.9 : 0.35))
                .setStroke()
            path.lineWidth = window.selected || window.focused ? 3 : 1
            if window.focused && !window.selected {
                path.setLineDash([10, 6], count: 2, phase: 0)
            }
            path.stroke()
            drawLabel(window.label.uppercased(), in: rect, selected: window.selected, dimmed: window.dimmed)
        }

        let rotateHint =
            model.selectedCount >= 2 ? "r / R rotate selected (\(model.selectedCount))" : "r / R rotate all"
        drawHelp(
            "labels select   ·   \(rotateHint)   ·   hjkl swap focused   ·   m swap with main   ·   esc done")
    }

    private func drawLabel(_ label: String, in rect: CGRect, selected: Bool, dimmed: Bool) {
        let text = NSAttributedString(
            string: label,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 28, weight: .bold),
                .foregroundColor: selected ? NSColor.white : NSColor.black.withAlphaComponent(dimmed ? 0.3 : 1),
            ])
        let size = text.size()
        let side = max(size.width, size.height) + 20
        let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        let fill = selected ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(dimmed ? 0.4 : 0.95)
        fill.setFill()
        NSBezierPath(roundedRect: box, xRadius: side / 2, yRadius: side / 2).fill()
        text.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
    }

    private func drawHelp(_ help: String) {
        let text = NSAttributedString(
            string: help,
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white])
        let size = text.size()
        let box = CGRect(
            x: bounds.midX - size.width / 2 - 16, y: bounds.maxY - size.height - 48,
            width: size.width + 32, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        text.draw(at: CGPoint(x: box.minX + 16, y: box.minY + 8))
    }
}
