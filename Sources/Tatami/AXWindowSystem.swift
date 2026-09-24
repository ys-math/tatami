import AppKit
import ApplicationServices
import TatamiCore

/// `WindowSystem` backed by the macOS Accessibility API.
@MainActor
struct AXWindowSystem: WindowSystem {
    func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return attribute(kAXFocusedWindowAttribute, of: appElement)
    }

    func windows() -> [AXUIElement] {
        // The on-screen window list is front-to-back and only covers the
        // current Space; AX windows are matched to it by process and frame.
        let onScreen = onScreenWindows()
        var ordered: [(index: Int, window: AXUIElement)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let windows: [AXUIElement] = attribute(kAXWindowsAttribute, of: appElement) ?? []
            for window in windows where isStandardVisibleWindow(window) {
                guard let frame = frame(of: window),
                    let index = onScreen.firstIndex(where: {
                        $0.pid == app.processIdentifier && $0.bounds.isClose(to: frame, tolerance: 1)
                    })
                else { continue }
                ordered.append((index, window))
            }
        }
        return ordered.sorted { $0.index < $1.index }.map(\.window)
    }

    func isResizable(_ window: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    func appIdentifier(of window: AXUIElement) -> String? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Normal-layer on-screen windows, frontmost first. Bounds and owner
    /// PIDs need no Screen Recording permission.
    private func onScreenWindows() -> [(pid: pid_t, bounds: CGRect)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { return nil }
            return (pid, bounds)
        }
    }

    private func isStandardVisibleWindow(_ window: AXUIElement) -> Bool {
        let subrole: String? = attribute(kAXSubroleAttribute, of: window)
        let minimized: Bool = attribute(kAXMinimizedAttribute, of: window) ?? false
        return subrole == kAXStandardWindowSubrole && !minimized
    }

    func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = attribute(kAXPositionAttribute, of: window),
            let sizeValue: AXValue = attribute(kAXSizeAttribute, of: window)
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    @discardableResult
    func setFrame(_ frame: CGRect, of window: AXUIElement) -> Bool {
        // Position, size, position: moving first lets the window grow into the
        // target display; the second move corrects apps that clamp on resize.
        var ok = setPosition(frame.origin, of: window)
        ok = setSize(frame.size, of: window) && ok
        ok = setPosition(frame.origin, of: window) && ok
        return ok
    }

    func displays() -> [Display] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let primaryHeight = primary.frame.height
        return screens.map { screen in
            Display(
                id: screen.uuidString,
                frame: Coordinates.flip(screen.frame, primaryHeight: primaryHeight),
                visibleFrame: Coordinates.flip(screen.visibleFrame, primaryHeight: primaryHeight)
            )
        }
    }

    // MARK: - Helpers

    private func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private func setPosition(_ point: CGPoint, of window: AXUIElement) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    private func setSize(_ size: CGSize, of window: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }
}

extension NSScreen {
    /// Stable per-display identifier, falling back to the localized name.
    var uuidString: String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = deviceDescription[key] as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return localizedName
    }
}
