import AppKit
import TatamiCore

/// Runs grid mode: shows the overlay, feeds keys to `GridModeState`, and
/// places the window that was focused when the mode began.
@MainActor
final class GridModeController<System: WindowSystem> {
    private let executor: CommandExecutor<System>
    private var session: Session?
    private var panel: OverlayPanel?

    private struct Session {
        var window: System.Window
        var displays: [Display]
        var state: GridModeState
    }

    init(executor: CommandExecutor<System>) {
        self.executor = executor
    }

    var isActive: Bool { session != nil }

    func begin() {
        guard session == nil else {
            end()
            return
        }
        let system = executor.system
        guard let window = system.focusedWindow(),
            let frame = system.frame(of: window)
        else { return }
        let displays = Display.sortedPhysically(system.displays())
        guard let display = Display.containing(frame, in: displays),
            let index = displays.firstIndex(of: display)
        else { return }

        let state = GridModeState(
            displayIndex: index, gridSizes: displays.map(executor.gridSize(for:)),
            selection: executor.grid(for: display).span(nearest: frame))
        session = Session(window: window, displays: displays, state: state)
        show()
    }

    func end() {
        session = nil
        panel?.orderOut(nil)
    }

    private func handle(_ input: GridModeInput) {
        guard var session else { return }
        let effect = session.state.handle(input)
        self.session = session

        switch effect {
        case .updated:
            show()
        case .ignored:
            NSSound.beep()
        case .gridChanged(let index, let size):
            executor.setGridSize(size, for: session.displays[index])
            show()
        case .apply(let index, let span):
            end()
            let grid = executor.grid(for: session.displays[index])
            executor.system.setFrame(grid.rect(for: span), of: session.window)
        case .cancel:
            end()
        }
    }

    private func show() {
        guard let session, let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let display = session.displays[session.state.displayIndex]
        let panel = self.panel ?? makePanel()
        self.panel = panel

        panel.setFrame(Coordinates.flip(display.frame, primaryHeight: primaryHeight), display: false)
        let view = GridModeView(frame: NSRect(origin: .zero, size: display.frame.size))
        view.model = GridModeView.Model(
            state: session.state,
            grid: Grid(size: session.state.gridSize, display: display, gaps: executor.config.gaps),
            origin: display.frame.origin)
        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel()
        panel.onKeyDown = { [weak self] event in
            if let input = GridModeKeys.input(for: event) {
                self?.handle(input)
            } else {
                NSSound.beep()
            }
        }
        panel.onCancel = { [weak self] in
            self?.handle(.cancel)
        }
        return panel
    }
}

/// Decodes key events for grid mode. `h j k l` and the control keys are read
/// by key code (physical position); labels by the typed character.
enum GridModeKeys {
    static func input(for event: NSEvent) -> GridModeInput? {
        input(
            keyCode: Int(event.keyCode), characters: event.charactersIgnoringModifiers ?? "",
            shift: event.modifierFlags.contains(.shift))
    }

    static func input(keyCode: Int, characters: String, shift: Bool) -> GridModeInput? {
        let directions: [Int: Direction] = [0x04: .left, 0x26: .down, 0x28: .up, 0x25: .right]
        if let direction = directions[keyCode] {
            return shift ? .resize(direction) : .move(direction)
        }
        switch keyCode {
        case 0x35: return .cancel  // Escape
        case 0x24, 0x4C: return .apply  // Return, keypad Enter
        case 0x30: return .nextDisplay  // Tab
        case 0x1B: return shift ? .adjustGrid(columns: 0, rows: -1) : .adjustGrid(columns: -1, rows: 0)  // - _
        case 0x18: return shift ? .adjustGrid(columns: 0, rows: 1) : .adjustGrid(columns: 1, rows: 0)  // = +
        default: break
        }
        guard characters.count == 1, let character = characters.lowercased().first,
            character.isLetter || character.isNumber
        else { return nil }
        return .character(character)
    }
}

/// A borderless panel covering one display that takes keyboard focus
/// without activating Tatami, so the target window's app stays frontmost.
final class OverlayPanel: NSPanel {
    var onKeyDown: (NSEvent) -> Void = { _ in }
    var onCancel: () -> Void = {}

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKeyDown(event)
    }

    override func mouseDown(with event: NSEvent) {
        onCancel()
    }

    override func resignKey() {
        super.resignKey()
        // Clicking another window or display ends the mode.
        if isVisible {
            onCancel()
        }
    }
}
