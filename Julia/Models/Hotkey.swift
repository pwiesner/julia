import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A global hotkey combination, stored as a Carbon key code + modifiers so
/// it can go straight into RegisterEventHotKey, plus the key's character
/// for display.
struct Hotkey: Codable, Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let key: String

    static let `default` = Hotkey(
        keyCode: UInt32(kVK_ANSI_T),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        key: "T"
    )

    init(keyCode: UInt32, carbonModifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.key = key
    }

    /// Builds a hotkey from a recorded key event. Returns nil when there is
    /// no chording modifier (plain typing, or shift alone) — a global hotkey
    /// must not swallow regular keys.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        guard modifiers & ~UInt32(shiftKey) != 0,
              let character = event.charactersIgnoringModifiers?.first else { return nil }
        self.init(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: modifiers,
            key: String(character).uppercased()
        )
    }

    /// "⌃⌥⇧⌘T"-style string in the standard macOS modifier order.
    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + key
    }

    /// SwiftUI equivalent for menu items; nil when the key has no simple
    /// character form (function keys and the like).
    var keyboardShortcut: KeyboardShortcut? {
        guard let character = key.lowercased().first else { return nil }
        var modifiers: SwiftUI.EventModifiers = []
        if carbonModifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }

    // MARK: - Persistence

    static let paletteDefaultsKey = "globalHotkey"
    static let jumpToAgentDefaultsKey = "jumpToAgentHotkey"

    static let jumpToAgentDefault = Hotkey(
        keyCode: UInt32(kVK_ANSI_J),
        carbonModifiers: UInt32(cmdKey | optionKey),
        key: "J"
    )

    static func saved(_ key: String, defaultingTo fallback: Hotkey) -> Hotkey {
        guard let data = UserDefaults.standard.data(forKey: key),
              let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data) else {
            return fallback
        }
        return hotkey
    }

    static var savedPalette: Hotkey { saved(paletteDefaultsKey, defaultingTo: .default) }
    static var savedJumpToAgent: Hotkey { saved(jumpToAgentDefaultsKey, defaultingTo: .jumpToAgentDefault) }

    func save(_ key: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
