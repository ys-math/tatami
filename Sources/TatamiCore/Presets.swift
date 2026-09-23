import CoreGraphics

/// Grid-independent placements.
public enum Presets {
    /// Fills the display's visible frame, inset by the outer gap.
    public static func maximize(on display: Display, gaps: Gaps) -> CGRect {
        area(of: display, gaps: gaps)
    }

    public static func leftHalf(on display: Display, gaps: Gaps) -> CGRect {
        let area = area(of: display, gaps: gaps)
        return CGRect(x: area.minX, y: area.minY, width: (area.width - gaps.inner) / 2, height: area.height)
    }

    public static func rightHalf(on display: Display, gaps: Gaps) -> CGRect {
        let area = area(of: display, gaps: gaps)
        let width = (area.width - gaps.inner) / 2
        return CGRect(x: area.maxX - width, y: area.minY, width: width, height: area.height)
    }

    /// Keeps the window's size (shrunk to fit if necessary) and centers it.
    public static func center(_ frame: CGRect, on display: Display, gaps: Gaps) -> CGRect {
        let area = area(of: display, gaps: gaps)
        let width = min(frame.width, area.width)
        let height = min(frame.height, area.height)
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    private static func area(of display: Display, gaps: Gaps) -> CGRect {
        display.visibleFrame.insetBy(dx: gaps.outer, dy: gaps.outer)
    }
}
