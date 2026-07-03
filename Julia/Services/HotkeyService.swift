import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyService {
    // nonisolated(unsafe) so deinit (which is nonisolated) can access these.
    // The Carbon callback also reads onToggle from a non-isolated context;
    // it's only assigned once during register() and dispatched back to the
    // main actor before invocation.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandler: EventHandlerRef?
    private nonisolated(unsafe) var onToggle: (() -> Void)?

    func register(hotkey: Hotkey, onToggle: @escaping () -> Void) {
        self.onToggle = onToggle

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    service.onToggle?()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )

        registerKey(hotkey)
    }

    /// Swaps the active binding, e.g. after the user records a new shortcut
    /// in settings. The event handler stays installed.
    func update(hotkey: Hotkey) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        registerKey(hotkey)
    }

    /// Registered system-wide via Carbon; no Accessibility permission needed.
    private func registerKey(_ hotkey: Hotkey) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4A554C49), id: 1) // 'JULI'
        RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

