import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyService {
    // Use nonisolated(unsafe) for properties accessed in deinit
    private nonisolated(unsafe) var globalMonitor: Any?
    private nonisolated(unsafe) var localMonitor: Any?
    private var onToggle: (() -> Void)?

    func register(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle

        // Global monitor for when app is not focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor for when app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }
    }

    func unregister() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    @discardableResult
    private nonisolated func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Check for Cmd+Shift+T
        let requiredFlags: NSEvent.ModifierFlags = [.command, .shift]
        let keyCode = Int(event.keyCode)

        // T key code is 17
        guard keyCode == kVK_ANSI_T,
              event.modifierFlags.contains(requiredFlags) else {
            return false
        }

        // Make sure no other modifiers are pressed
        let unwantedFlags: NSEvent.ModifierFlags = [.control, .option]
        guard !event.modifierFlags.contains(unwantedFlags) else {
            return false
        }

        Task { @MainActor [weak self] in
            self?.onToggle?()
        }
        return true
    }

    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Accessibility Permission Helper

@MainActor
enum AccessibilityHelper {
    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        // The string value of kAXTrustedCheckOptionPrompt is "AXTrustedCheckOptionPrompt"
        // Using the string directly avoids concurrency issues with the C global
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
