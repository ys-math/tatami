import AppKit
import TatamiCore

/// Draws the grid mode overlay for one display, in AX-style (flipped) coordinates.
final class GridModeView: NSView {
    struct Model {
        var state: GridModeState
        var grid: Grid
        /// The display's top-left corner in AX coordinates.
        var origin: CGPoint
    }

    var model: Model?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let state = model.state
        let shift = { (rect: CGRect) in rect.offsetBy(dx: -model.origin.x, dy: -model.origin.y) }

        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        let labels = state.labels
        for (index, cell) in model.grid.cellRects().enumerated() {
            let rect = shift(cell)
            let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            NSColor.white.withAlphaComponent(0.06).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 1
            path.stroke()

            let label = labels[index]
            let matches = state.typed.isEmpty || label.hasPrefix(state.typed)
            drawLabel(label.uppercased(), in: rect, highlighted: !state.typed.isEmpty && matches, dimmed: !matches)
        }

        let selection = NSBezierPath(
            roundedRect: shift(model.grid.rect(for: state.selection)), xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
        selection.fill()
        NSColor.controlAccentColor.setStroke()
        selection.lineWidth = 3
        selection.stroke()

        if let corner = state.corner {
            let path = NSBezierPath(roundedRect: shift(model.grid.rect(for: corner)), xRadius: 10, yRadius: 10)
            NSColor.white.setStroke()
            path.lineWidth = 3
            path.setLineDash([8, 6], count: 2, phase: 0)
            path.stroke()
        }

        drawHelp(
            "\(state.gridSize.columns) × \(state.gridSize.rows)   ·   labels: two corners   ·   hjkl move   ·   "
                + "HJKL resize   ·   - = columns   ·   _ + rows   ·   ⇥ next display   ·   ⏎ apply   ·   esc cancel")
    }

    private func drawLabel(_ label: String, in rect: CGRect, highlighted: Bool, dimmed: Bool) {
        let size = min(rect.width, rect.height, 120) * 0.35
        let color: NSColor =
            highlighted ? .systemYellow : .white.withAlphaComponent(dimmed ? 0.2 : 0.85)
        let text = NSAttributedString(
            string: label,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: max(size, 12), weight: .bold),
                .foregroundColor: color,
            ])
        let textSize = text.size()
        text.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
    }

    private func drawHelp(_ help: String) {
        let text = NSAttributedString(
            string: help,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white,
            ])
        let size = text.size()
        let box = CGRect(
            x: bounds.midX - size.width / 2 - 16, y: bounds.maxY - size.height - 48,
            width: size.width + 32, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        text.draw(at: CGPoint(x: box.minX + 16, y: box.minY + 8))
    }
}
