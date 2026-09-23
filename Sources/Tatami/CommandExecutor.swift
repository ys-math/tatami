import CoreGraphics
import TatamiCore

enum Command: Equatable {
    case maximize
}

/// Turns commands into frame changes: snapshot the focused window, ask
/// `TatamiCore` for the target frame, apply it.
@MainActor
struct CommandExecutor<System: WindowSystem> {
    let system: System
    var outerGap: CGFloat = 8

    @discardableResult
    func execute(_ command: Command) -> Bool {
        guard let window = system.focusedWindow(),
            let current = system.frame(of: window),
            let display = Display.containing(current, in: system.displays())
        else { return false }

        let target: CGRect
        switch command {
        case .maximize:
            target = Presets.maximize(on: display, outerGap: outerGap)
        }
        return system.setFrame(target, of: window)
    }
}
