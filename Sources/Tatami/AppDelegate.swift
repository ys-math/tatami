import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let accessibilityItem = NSMenuItem()
    private let executor = CommandExecutor(system: AXWindowSystem())

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        Accessibility.requestTrust()
        registerHotKeys()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.grid.2x2", accessibilityDescription: "Tatami")

        let menu = NSMenu()
        menu.delegate = self
        accessibilityItem.target = self
        accessibilityItem.action = #selector(openAccessibilitySettings)
        menu.addItem(accessibilityItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Tatami", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateAccessibilityItem()
    }

    private func registerHotKeys() {
        // Phase 1: a single hard-coded binding proving the end-to-end path.
        do {
            try HotKeyCenter.shared.register(keyCode: kVK_Return, modifiers: [.control, .option]) {
                [executor] in
                executor.execute(.maximize)
            }
        } catch {
            NSLog("Tatami: failed to register hotkey: \(error)")
        }
    }

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
