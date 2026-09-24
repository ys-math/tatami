import AppKit
import TatamiCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let accessibilityItem = NSMenuItem()
    private let problemsSeparator = NSMenuItem.separator()
    private var problemItems: [NSMenuItem] = []
    private let files = SettingsFiles.standard
    private lazy var executor = CommandExecutor(system: AXWindowSystem(), gridState: files.loadState())
    private let gridFlash = GridFlash()
    private lazy var gridMode = GridModeController(executor: executor)
    private lazy var boundaryMode = BoundaryModeController(executor: executor)
    private lazy var windowMode = WindowModeController(executor: executor)
    private lazy var focusHints = FocusHintController(executor: executor)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        Accessibility.requestTrust()
        executor.onGridStateChange = { [files] state in
            do {
                try files.saveState(state)
            } catch {
                NSLog("Tatami: failed to save state: \(error)")
            }
        }
        executor.onGridAdjusted = { [gridFlash] grid, display in
            gridFlash.show(grid, on: display)
        }
        executor.onArranged = { [gridFlash] layout, display in
            gridFlash.show(label: layout.displayName, on: display)
        }
        reloadConfig()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.grid.2x2", accessibilityDescription: "Tatami")

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        accessibilityItem.target = self
        accessibilityItem.action = #selector(openAccessibilitySettings)
        menu.addItem(accessibilityItem)
        menu.addItem(.separator())
        menu.addItem(item("Open Config", #selector(openConfig), key: ","))
        menu.addItem(item("Reload Config", #selector(reloadConfigFromMenu), key: "r"))
        problemsSeparator.isHidden = true
        menu.addItem(problemsSeparator)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Tatami", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateAccessibilityItem()
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Config

    /// Loads the config and re-registers hotkeys. On error the previous
    /// config stays active and the error is shown in the menu.
    private func reloadConfig() {
        var problems: [String] = []
        switch files.loadConfig() {
        case .success(let config):
            executor.config = config
        case .failure(let error):
            problems.append("Config error: \(error)")
        }
        problems += registerHotKeys(executor.config.bindings)
        showProblems(problems)
    }

    /// Returns a message for each binding that could not be registered.
    private func registerHotKeys(_ bindings: [Action: Hotkey]) -> [String] {
        HotKeyCenter.shared.unregisterAll()
        var problems: [String] = []
        for (action, hotkey) in bindings.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            do {
                try HotKeyCenter.shared.register(hotkey) { [weak self] in
                    self?.perform(action)
                }
            } catch {
                problems.append("\(hotkey) (\(action.rawValue)) is unavailable — used by another app?")
            }
        }
        return problems
    }

    private func perform(_ action: Action) {
        // Any hotkey leaves an open mode first; a mode's own hotkey toggles it.
        let wasInGridMode = gridMode.isActive
        let wasInBoundaryMode = boundaryMode.isActive
        let wasInWindowMode = windowMode.isActive
        let wasInFocusHints = focusHints.isActive
        gridMode.end()
        boundaryMode.end()
        windowMode.end()
        focusHints.end()
        switch action {
        case .gridMode:
            if !wasInGridMode { gridMode.begin() }
        case .boundaryMode:
            if !wasInBoundaryMode { boundaryMode.begin() }
        case .windowCommand:
            if !wasInWindowMode { windowMode.begin() }
        case .focusHints:
            if !wasInFocusHints { focusHints.begin() }
        default:
            executor.execute(action)
        }
    }

    private func showProblems(_ problems: [String]) {
        guard let menu = statusItem.menu else { return }
        problemItems.forEach(menu.removeItem)
        problemItems = problems.map { message in
            let item = NSMenuItem(title: "⚠︎ \(message)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        let index = menu.index(of: problemsSeparator) + 1
        for (offset, item) in problemItems.enumerated() {
            menu.insertItem(item, at: index + offset)
        }
        problemsSeparator.isHidden = problems.isEmpty
        for problem in problems {
            NSLog("Tatami: \(problem)")
        }
    }

    @objc private func openConfig() {
        try? files.writeDefaultConfigIfMissing()
        NSWorkspace.shared.open(files.configURL)
    }

    @objc private func reloadConfigFromMenu() {
        reloadConfig()
    }

    // MARK: - Accessibility

    private func updateAccessibilityItem() {
        if Accessibility.isTrusted {
            accessibilityItem.title = "Accessibility: Granted"
            accessibilityItem.state = .on
        } else {
            accessibilityItem.title = "Accessibility: Not Granted — Open Settings…"
            accessibilityItem.state = .off
        }
    }

    @objc private func openAccessibilitySettings() {
        Accessibility.openSettings()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateAccessibilityItem()
    }
}
