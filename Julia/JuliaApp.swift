import SwiftUI

@main
struct JuliaApp: App {
    @State private var viewModel = PaletteViewModel()
    @State private var paletteController = PaletteWindowController()
    @State private var hotkeyService = HotkeyService()
    @State private var agentMonitor = AgentMonitorService()

    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                onShowPalette: showPalette,
                onJumpToAgent: jumpToWaitingAgent,
                onOpenSettings: openSettingsInFront,
                onQuit: { NSApp.terminate(nil) }
            )
        } label: {
            MenuBarLabel(monitor: agentMonitor)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(hotkeyService: hotkeyService)
        }
    }

    init() {
        setupHotkey()
    }

    private func setupHotkey() {
        Task { @MainActor in
            hotkeyService.register(.togglePalette, hotkey: .savedPalette) { [self] in
                togglePalette()
            }
            hotkeyService.register(.jumpToAgent, hotkey: .savedJumpToAgent) { [self] in
                jumpToWaitingAgent()
            }
            agentMonitor.start()
        }
    }

    private func jumpToWaitingAgent() {
        paletteController.hide()
        agentMonitor.jumpToLongestWaiting()
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

    /// The palette floats above normal windows, so it must go away before
    /// the settings window can be seen. As an LSUIElement app we're never
    /// active either, so activate explicitly or settings opens behind the
    /// frontmost app.
    private func openSettingsInFront() {
        paletteController.hide()
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}

struct MenuBarView: View {
    let onShowPalette: () -> Void
    let onJumpToAgent: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        Button("Show Palette") {
            onShowPalette()
        }
        .keyboardShortcut(Hotkey.savedPalette.keyboardShortcut)

        Button("Jump to Waiting Agent") {
            onJumpToAgent()
        }
        .keyboardShortcut(Hotkey.savedJumpToAgent.keyboardShortcut)

        Divider()

        Button("Settings...") {
            onOpenSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Julia") {
            onQuit()
        }
        .keyboardShortcut("q")
    }
}

