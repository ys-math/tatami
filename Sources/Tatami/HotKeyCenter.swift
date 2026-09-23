import Carbon.HIToolbox
import TatamiCore

/// Registers system-wide hotkeys through Carbon's `RegisterEventHotKey`,
/// which needs no Input Monitoring permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    struct Modifiers: OptionSet, Sendable {
        let rawValue: UInt32
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let option = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
        static let shift = Modifiers(rawValue: UInt32(shiftKey))
    }

    enum Error: Swift.Error {
        case installHandlerFailed(OSStatus)
        case registerFailed(OSStatus)
    }

    /// Four-char code 'TTMI' identifying Tatami's hotkeys.
    private static let signature: OSType = 0x5454_4D49

    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    private init() {}

    @discardableResult
    func register(_ hotkey: Hotkey, action: @escaping @MainActor () -> Void) throws -> UInt32 {
        var modifiers: Modifiers = []
        if hotkey.modifiers.contains(.control) { modifiers.insert(.control) }
        if hotkey.modifiers.contains(.option) { modifiers.insert(.option) }
        if hotkey.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if hotkey.modifiers.contains(.command) { modifiers.insert(.command) }
        return try register(keyCode: hotkey.keyCode, modifiers: modifiers, action: action)
    }

    @discardableResult
    func register(
        keyCode: Int, modifiers: Modifiers, action: @escaping @MainActor () -> Void
    ) throws -> UInt32 {
        try installHandlerIfNeeded()
        let id = nextID
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), modifiers.rawValue, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { throw Error.registerFailed(status) }
        nextID += 1
        refs[id] = ref
        actions[id] = action
        return id
    }

    func unregisterAll() {
        for ref in refs.values {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        actions.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() throws {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, &handler)
        guard status == noErr else { throw Error.installHandlerFailed(status) }
    }
}

/// Carbon delivers hotkey events on the main thread.
private func hotKeyHandler(
    _: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    MainActor.assumeIsolated {
        HotKeyCenter.shared.fire(hotKeyID.id)
    }
    return noErr
}
