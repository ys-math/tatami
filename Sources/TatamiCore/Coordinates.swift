import CoreGraphics

/// Conversions between AppKit screen coordinates (bottom-left origin, y up)
/// and Accessibility coordinates (top-left origin of the primary display, y down).
public enum Coordinates {
    /// Converts a rect between AppKit and AX space. The transform is its own inverse.
    /// - Parameter primaryHeight: height of the primary display (the one at origin 0,0).
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
