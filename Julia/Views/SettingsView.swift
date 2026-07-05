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

    private static let repositoryURL = URL(string: "https://github.com/pwiesner/julia")
    private static let releasesURL = URL(string: "https://github.com/pwiesner/julia/releases")

    var body: some View {
        Form {
            Section("Appearance") {
                // One appearance for all of julia's windows, this one
                // included — a dark palette with light settings reads
                // like two apps.
                Picker("Appearance", selection: $appearanceRaw) {
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

                Text("Click a key, then press the new combination. It needs at least one of ⌘, ⌥, or ⌃. Press ⌘/ in the palette for the full keymap.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HealthSectionView()

            Section("About") {
                LabeledContent("Julia \(appVersion)") {
                    HStack(spacing: 14) {
                        if let releases = Self.releasesURL {
                            Link("releases", destination: releases)
                        }
                        if let repository = Self.repositoryURL {
                            Link("github", destination: repository)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 620)
        .preferredColorScheme(PaletteAppearance(rawValue: appearanceRaw)?.colorScheme)
        .onDisappear(perform: stopRecording)
    }

    private func recorderRow(_ title: String, slot: HotkeyService.Slot, current: Hotkey) -> some View {
        LabeledContent(title) {
            Button {
                toggleRecording(for: slot)
            } label: {
                KeycapView(keys: recordingSlot == slot ? "type shortcut… (esc cancels)" : current.displayString)
            }
            .buttonStyle(.plain)
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
