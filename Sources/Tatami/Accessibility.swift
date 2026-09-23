import AppKit
import ApplicationServices

enum Accessibility {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt asking the user to grant Accessibility access.
    @discardableResult
    static func requestTrust() -> Bool {
        // Literal value of `kAXTrustedCheckOptionPrompt`, whose global var is
        // not concurrency-safe under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
