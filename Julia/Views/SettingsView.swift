import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    let hotkeyService: HotkeyService?

    @State private var paletteHotkey = Hotkey.savedPalette
    @State private var jumpHotkey = Hotkey.savedJumpToAgent
    @State private var recordingSlot: HotkeyService.Slot?
    @State private var recordingMonitor: Any?
    @AppStorage(PaletteAppearance.defaultsKey) private var appearanceRaw = PaletteAppearance.dark.rawValue
    @AppStorage(NotificationMode.defaultsKey) private var notificationModeRaw = NotificationMode.permissionRequests.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Palette theme", selection: $appearanceRaw) {
                    ForEach(PaletteAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Notifications") {
                Picker("Notify when agents wait", selection: $notificationModeRaw) {
                    ForEach(NotificationMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text("Permission requests block a running task; \"All waits\" also notifies whenever an agent finishes and wants a reply.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard Shortcuts") {
                recorderRow("Toggle Palette", slot: .togglePalette, current: paletteHotkey)
                recorderRow("Jump to Waiting Agent", slot: .jumpToAgent, current: jumpHotkey)

                Text("Click, then press the new combination. It needs at least one of ⌘, ⌥, or ⌃.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("tmux") {
                    Text("Required for operation")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
        .onDisappear(perform: stopRecording)
    }

    private func recorderRow(_ title: String, slot: HotkeyService.Slot, current: Hotkey) -> some View {
        LabeledContent(title) {
            Button {
                toggleRecording(for: slot)
            } label: {
                Text(recordingSlot == slot ? "Type shortcut… (esc cancels)" : current.displayString)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 160)
            }
        }
    }

    private func toggleRecording(for slot: HotkeyService.Slot) {
        let wasRecording = recordingSlot == slot
        stopRecording()
        if !wasRecording {
            startRecording(for: slot)
        }
    }

    private func startRecording(for slot: HotkeyService.Slot) {
        recordingSlot = slot
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
            } else if let recorded = Hotkey(event: event) {
                apply(recorded)
                stopRecording()
            }
            // Swallow keystrokes while recording so they don't reach the form.
            return nil
        }
    }

    private func stopRecording() {
        recordingSlot = nil
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
    }

    private func apply(_ recorded: Hotkey) {
        switch recordingSlot {
        case .togglePalette:
            paletteHotkey = recorded
            recorded.save(Hotkey.paletteDefaultsKey)
            hotkeyService?.update(.togglePalette, hotkey: recorded)
        case .jumpToAgent:
            jumpHotkey = recorded
            recorded.save(Hotkey.jumpToAgentDefaultsKey)
            hotkeyService?.update(.jumpToAgent, hotkey: recorded)
        case nil:
            break
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

#Preview {
    SettingsView(hotkeyService: nil)
}
