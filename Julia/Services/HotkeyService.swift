import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyService {
    /// Each global shortcut the app owns. The raw value doubles as the
    /// Carbon hot key id, which is how the event handler routes a press
    /// back to the right action.
    enum Slot: UInt32 {
        case togglePalette = 1
        case jumpToAgent = 2
    }

    // nonisolated(unsafe) so deinit (which is nonisolated) can access these.
    // The Carbon callback also reads actions from a non-isolated context;
    // entries are only mutated on the main actor and the callback dispatches
    // back to it before invoking anything.
    private nonisolated(unsafe) var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private nonisolated(unsafe) var actions: [UInt32: () -> Void] = [:]
    private nonisolated(unsafe) var eventHandler: EventHandlerRef?

    func register(_ slot: Slot, hotkey: Hotkey, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        actions[slot.rawValue] = action
        registerKey(hotkey, slot: slot)
    }

    /// Swaps a slot's binding, e.g. after the user records a new shortcut
    /// in settings. The event handler stays installed.
    func update(_ slot: Slot, hotkey: Hotkey) {
        if let ref = hotKeyRefs[slot.rawValue] {
            UnregisterEventHotKey(ref)
            hotKeyRefs[slot.rawValue] = nil
        }
        registerKey(hotkey, slot: slot)
    }

    func unregister() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs = [:]
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    // MARK: - Private

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                Task { @MainActor in
                    service.actions[id]?()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
    }

    /// Registered system-wide via Carbon; no Accessibility permission needed.
    private func registerKey(_ hotkey: Hotkey, slot: Slot) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4A554C49), id: slot.rawValue) // 'JULI'
        var ref: EventHotKeyRef?
        RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        hotKeyRefs[slot.rawValue] = ref
    }

    deinit {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
