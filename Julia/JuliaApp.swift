import SwiftUI

@main
struct JuliaApp: App {
    @State private var viewModel = PaletteViewModel()
    @State private var paletteController = PaletteWindowController()
    @State private var hotkeyService = HotkeyService()
    @State private var agentMonitor = AgentMonitorService()
    @State private var notificationService = NotificationService()

    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                monitor: agentMonitor,
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
            paletteController.onHide = { [viewModel] in
                viewModel.stopPreview()
                viewModel.paletteDidHide()
            }
            hotkeyService.register(.togglePalette, hotkey: .savedPalette) { [self] in
                togglePalette()
            }
            hotkeyService.register(.jumpToAgent, hotkey: .savedJumpToAgent) { [self] in
                jumpToWaitingAgent()
            }
            notificationService.onJump = { [agentMonitor] sessionName, windowIndex in
                agentMonitor.jump(toSession: sessionName, windowIndex: windowIndex)
            }
            notificationService.activate()
            agentMonitor.notifications = notificationService
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
        let wasAlreadyOpen = settingsWindow?.isVisible == true
        openSettings()

        // macOS restores the frame saved by older, smaller layouts, so a
        // grown window ends up hugging the dock. Center fresh opens; an
        // already-open window keeps wherever the user put it.
        guard !wasAlreadyOpen else { return }
        Task { @MainActor in
            for _ in 0..<10 {
                if let window = settingsWindow {
                    window.center()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private var settingsWindow: NSWindow? {
        NSApp.windows.first {
            $0.identifier?.rawValue.contains("Settings") == true || $0.title == "Julia Settings"
        }
    }
}

struct MenuBarView: View {
    let monitor: AgentMonitorService
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

        // The badge says how many need you; this says who and what for,
        // one click from being there — triage without the palette.
        if !monitor.waitingWindows.isEmpty {
            Divider()
            Section("Needs you") {
                ForEach(monitor.waitingWindows) { window in
                    Button {
                        monitor.jump(toSession: window.sessionName, windowIndex: window.index)
                    } label: {
                        Label(
                            Self.menuTitle(for: window),
                            systemImage: window.agentGlyph ?? "bubble.left.fill"
                        )
                    }
                }
            }
        }

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

    /// Menu items get one modest line: where the agent is, then a short
    /// slice of its task, which is what tells same-project agents apart.
    private static func menuTitle(for window: TmuxWindow) -> String {
        let place = "\(window.sessionName):\(window.index) \(window.displayName)"
        guard var task = window.agentTask else { return place }
        if task.count > 40 {
            task = task.prefix(40).trimmingCharacters(in: .whitespaces) + "…"
        }
        return "\(place) — “\(task)”"
    }
}

