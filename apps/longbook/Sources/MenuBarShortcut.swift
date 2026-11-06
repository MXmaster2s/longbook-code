#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// A key and its modifiers, kept as "keyCode modifiers label": Carbon's own numbers, so the
/// stored value registers as it is, and the label drawn when it was recorded.
struct KeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    init?(stored: String) {
        let parts = stored.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3, let key = UInt32(parts[0]), let mods = UInt32(parts[1]) else { return nil }
        self.init(keyCode: key, modifiers: mods, label: parts[2])
    }

    var stored: String { "\(keyCode) \(modifiers) \(label)" }

    /// A key press as a combo, or nil when it has no Command, Control or Option: a bare
    /// letter would fire while typing anywhere.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        var mods: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { mods |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { mods |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { mods |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { mods |= UInt32(cmdKey); symbols += "⌘" }
        let code = Int(event.keyCode)
        let key = Self.named[code] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.init(keyCode: UInt32(code), modifiers: mods, label: symbols + key)
    }

    /// Keys whose character prints as nothing, or as something unreadable.
    private static let named: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// The keyboard shortcut that opens the menu bar panel from any app. Carbon's hot keys need
/// no Accessibility permission, so they work in the sandbox. None is set until one is recorded.
@MainActor
enum MenuBarShortcut {
    static let key = "longbook.menuBar.shortcut"

    private static var registered: EventHotKeyRef?
    private static var handlerInstalled = false

    static var stored: KeyCombo? {
        UserDefaults.standard.string(forKey: key).flatMap(KeyCombo.init(stored:))
    }

    /// At launch: the shortcut as it was left.
    static func applyStored() {
        if let combo = stored { _ = register(combo) }
    }

    /// Saves and registers a combo, or clears it with nil. Returns false when another app
    /// already holds that combo; nothing is saved then.
    @discardableResult
    static func set(_ combo: KeyCombo?) -> Bool {
        unregister()
        guard let combo else {
            UserDefaults.standard.removeObject(forKey: key)
            return true
        }
        guard register(combo) else {
            applyStored()
            return false
        }
        UserDefaults.standard.set(combo.stored, forKey: key)
        return true
    }

    /// Lets the recorder hear the current combo instead of the panel opening.
    static func pause() { unregister() }

    private static func register(_ combo: KeyCombo) -> Bool {
        installHandler()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4C4E_4742), id: 1) // "LNGB"
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        registered = ref
        return true
    }

    private static func unregister() {
        if let registered { UnregisterEventHotKey(registered) }
        registered = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Later, not inside Carbon's callback: the menu tracks modally until it closes.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Measure.used("menu_bar_shortcut", .shortcut)
                    MenuBarPanel.open()
                }
            }
            return noErr
        }, 1, &type, nil, nil)
    }
}

/// Opens the MenuBarExtra's menu by clicking its status item button, the one way SwiftUI
/// leaves open. The button lives in the app's NSStatusBarWindow.
@MainActor
enum MenuBarPanel {
    static func open() {
        let window = NSApp.windows.first { String(describing: type(of: $0)).contains("NSStatusBarWindow") }
        guard let view = window?.contentView, let button = statusButton(in: view) else { return }
        button.performClick(nil)
    }

    private static func statusButton(in view: NSView) -> NSButton? {
        if let button = view as? NSStatusBarButton { return button }
        for sub in view.subviews {
            if let found = statusButton(in: sub) { return found }
        }
        return nil
    }
}
#endif
