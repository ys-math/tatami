import CoreGraphics

/// Grid-independent placements.
public enum Presets {
    /// Fills the display's visible frame, inset by the outer gap.
    public static func maximize(on display: Display, outerGap: CGFloat) -> CGRect {
        display.visibleFrame.insetBy(dx: outerGap, dy: outerGap)
    }
}
