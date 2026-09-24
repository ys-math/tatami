import AppKit
import ServiceManagement
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
    private let launchAtLoginItem = NSMenuItem()
    private var configWatcher: ConfigWatcher?
    /// The config file contents last loaded, so saves of `state.json` or
    /// unchanged rewrites in the same directory don't trigger a reload.
    private var loadedConfigData: Data?

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
        configWatcher = ConfigWatcher(directory: files.directory) { [weak self] in
            self?.reloadConfigIfChanged()
        }
        configWatcher?.start()
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
        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Tatami", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateAccessibilityItem()
        updateLaunchAtLoginItem()
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
        loadedConfigData = try? Data(contentsOf: files.configURL)
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

    /// Called by the directory watcher: reloads only if `config.json` changed.
    private func reloadConfigIfChanged() {
        let data = try? Data(contentsOf: files.configURL)
        guard data != loadedConfigData else { return }
        reloadConfig()
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

    // MARK: - Launch at login

    private func updateLaunchAtLoginItem() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginItem.title = "Launch at Login"
            launchAtLoginItem.state = .on
        case .requiresApproval:
            launchAtLoginItem.title = "Launch at Login — Approve in System Settings…"
            launchAtLoginItem.state = .mixed
        default:
            launchAtLoginItem.title = "Launch at Login"
            launchAtLoginItem.state = .off
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
            }
        } catch {
            NSLog("Tatami: launch at login failed: \(error)")
            NSSound.beep()
        }
        updateLaunchAtLoginItem()
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
        updateLaunchAtLoginItem()
    }
}
