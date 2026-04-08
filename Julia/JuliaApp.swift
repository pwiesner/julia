import SwiftUI

@main
struct JuliaApp: App {
    @State private var viewModel = PaletteViewModel()
    @State private var paletteController = PaletteWindowController()
    @State private var hotkeyService = HotkeyService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                onShowPalette: showPalette,
                onQuit: { NSApp.terminate(nil) }
            )
        } label: {
            Image(systemName: "terminal")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }

    init() {
        setupHotkey()
    }

    private func setupHotkey() {
        Task { @MainActor in
            hotkeyService.register { [self] in
                togglePalette()
            }
        }
    }

    private func showPalette() {
        let paletteView = PaletteView(
            viewModel: viewModel,
            onDismiss: { paletteController.hide() }
        )
        paletteController.show(content: paletteView)
    }

    private func togglePalette() {
        if paletteController.isVisible {
            paletteController.hide()
        } else {
            showPalette()
        }
    }
}

struct MenuBarView: View {
    let onShowPalette: () -> Void
    let onQuit: () -> Void

    var body: some View {
        Button("Show Palette") {
            onShowPalette()
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])

        Divider()

        SettingsLink {
            Text("Settings...")
        }

        Divider()

        Button("Quit Julia") {
            onQuit()
        }
        .keyboardShortcut("q")
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Keyboard Shortcut") {
                LabeledContent("Toggle Palette") {
                    Text("Cmd + Shift + T")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text("1.0")
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
    }
}

#Preview("Settings") {
    SettingsView()
}
