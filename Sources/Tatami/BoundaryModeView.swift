import AppKit
import TatamiCore

/// Draws boundary mode for one display, in AX-style (flipped) coordinates.
final class BoundaryModeView: NSView {
    struct Line {
        var axis: Axis
        var position: CGFloat
        var extent: ClosedRange<CGFloat>
    }

    struct Item {
        /// One line for a boundary, both lines for a crosspoint.
        var lines: [Line]
        var anchor: CGPoint
        var isCrosspoint: Bool
    }

    struct Model {
        var items: [Item]
        var labels: [String]
        var selectedIndex: Int
        var typed: String
        var windows: [CGRect]
        var innerGap: CGFloat
        /// The display's top-left corner in AX coordinates.
        var origin: CGPoint

        init<ID: Hashable>(
            items: [BoundaryItem<ID>], labels: [String], selectedIndex: Int, typed: String, windows: [CGRect],
            innerGap: CGFloat, origin: CGPoint
        ) {
            func line(_ boundary: Boundary<ID>) -> Line {
                Line(axis: boundary.axis, position: boundary.position, extent: boundary.extent)
            }
            self.items = items.map { item in
                switch item {
                case .boundary(let boundary):
                    Item(lines: [line(boundary)], anchor: item.anchor, isCrosspoint: false)
                case .crosspoint(let crosspoint):
                    Item(
                        lines: [line(crosspoint.vertical), line(crosspoint.horizontal)], anchor: item.anchor,
                        isCrosspoint: true)
                }
            }
            self.labels = labels
            self.selectedIndex = selectedIndex
            self.typed = typed
            self.windows = windows
            self.innerGap = innerGap
            self.origin = origin
        }
    }

    var model: Model?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let offset = CGPoint(x: -model.origin.x, y: -model.origin.y)

        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        for window in model.windows {
            let path = NSBezierPath(
                roundedRect: window.offsetBy(dx: offset.x, dy: offset.y), xRadius: 8, yRadius: 8)
            NSColor.white.withAlphaComponent(0.05).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.25).setStroke()
            path.stroke()
        }

        // Lines first, then crosspoints and labels on top.
        for (index, item) in model.items.enumerated() where !item.isCrosspoint {
            for line in item.lines {
                drawLine(line, selected: index == model.selectedIndex, offset: offset, width: model.innerGap)
            }
        }
        for (index, item) in model.items.enumerated() {
            let selected = index == model.selectedIndex
            let anchor = CGPoint(x: item.anchor.x + offset.x, y: item.anchor.y + offset.y)
            if item.isCrosspoint && selected {
                for line in item.lines {
                    drawLine(line, selected: true, offset: offset, width: model.innerGap)
                }
            }
            let label = model.labels[index]
            let matches = model.typed.isEmpty || label.hasPrefix(model.typed)
            drawBadge(
                label.uppercased(), at: anchor, round: item.isCrosspoint, selected: selected,
                dimmed: !matches)
        }

        drawHelp(
            "hjkl move to grid line   ·   HJKL fine step   ·   labels / ⇥ select   ·   ⏎ or esc done")
    }

    private func drawLine(_ boundary: Line, selected: Bool, offset: CGPoint, width: CGFloat) {
        let thickness = max(width, 4)
        let rect: CGRect
        if boundary.axis == .horizontal {
            rect = CGRect(
                x: boundary.position - thickness / 2 + offset.x, y: boundary.extent.lowerBound + offset.y,
                width: thickness, height: boundary.extent.upperBound - boundary.extent.lowerBound)
        } else {
            rect = CGRect(
                x: boundary.extent.lowerBound + offset.x, y: boundary.position - thickness / 2 + offset.y,
                width: boundary.extent.upperBound - boundary.extent.lowerBound, height: thickness)
        }
        (selected ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.5)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }

    private func drawBadge(_ label: String, at point: CGPoint, round: Bool, selected: Bool, dimmed: Bool) {
        let text = NSAttributedString(
            string: label,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold),
                .foregroundColor: selected ? NSColor.white : NSColor.black.withAlphaComponent(dimmed ? 0.3 : 1),
            ])
        let size = text.size()
        let side = max(size.width, size.height) + 14
        let box = CGRect(
            x: point.x - (round ? side : size.width + 20) / 2, y: point.y - side / 2,
            width: round ? side : size.width + 20, height: side)
        let base: NSColor = round ? .systemYellow : .white
        let fill = selected ? NSColor.controlAccentColor : base.withAlphaComponent(dimmed ? 0.4 : 0.95)
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
