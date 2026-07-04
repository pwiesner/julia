import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    let hotkeyService: HotkeyService?

    @State private var hotkey = Hotkey.saved
    @State private var isRecording = false
    @State private var recordingMonitor: Any?
    @AppStorage(PaletteAppearance.defaultsKey) private var appearanceRaw = PaletteAppearance.dark.rawValue

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

            Section("Keyboard Shortcut") {
                LabeledContent("Toggle Palette") {
                    Button(action: toggleRecording) {
                        Text(isRecording ? "Type shortcut… (esc cancels)" : hotkey.displayString)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 160)
                    }
                }

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

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
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
        isRecording = false
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
    }

    private func apply(_ recorded: Hotkey) {
        hotkey = recorded
        recorded.save()
        hotkeyService?.update(hotkey: recorded)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

#Preview {
    SettingsView(hotkeyService: nil)
}
