import CoreGraphics
import TatamiCore

/// Access to on-screen windows and displays, in AX coordinates.
///
/// The AX-backed implementation is `AXWindowSystem`; tests use a fake.
@MainActor
protocol WindowSystem {
    associatedtype Window

    /// The focused window of the frontmost application, if any.
    func focusedWindow() -> Window?
    func frame(of window: Window) -> CGRect?
    /// Returns `false` if the window rejected the change.
    @discardableResult
    func setFrame(_ frame: CGRect, of window: Window) -> Bool
    func displays() -> [Display]
}
