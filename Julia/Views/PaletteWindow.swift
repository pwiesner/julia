import AppKit
import SwiftUI

/// NSPanel refuses key status by default for borderless-style panels;
/// a command palette must accept it so the search field gets keystrokes
/// while the previously active app keeps focus (.nonactivatingPanel).
private final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PaletteWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private nonisolated(unsafe) var clickMonitor: Any?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show<Content: View>(content: Content) {
        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        let hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]

        panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
        panel.contentView?.addSubview(hostingView)
        self.hostingView = hostingView

        positionPanel()
        // No NSApp.activate(): the nonactivating panel takes key status
        // while the terminal stays the active app, so dismissing the
        // palette leaves keyboard focus exactly where it was.
        panel.makeKeyAndOrderFront(nil)

        setupClickOutsideMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        removeClickOutsideMonitor()
        // If something did activate us (e.g. opening via the menu bar),
        // step aside so focus returns to the previous app.
        if NSApp.isActive {
            NSApp.hide(nil)
        }
    }

    func toggle<Content: View>(content: Content) {
        if isVisible {
            hide()
        } else {
            show(content: content)
        }
    }

    private func createPanel() {
        let panel = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 620),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Make it behave like a command palette
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false

        self.panel = panel
    }

    private func positionPanel() {
        guard let panel,
              let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size

        let x = screenFrame.midX - (panelSize.width / 2)
        let y = screenFrame.midY + (screenFrame.height / 4) - (panelSize.height / 2)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func setupClickOutsideMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self,
                  let panel = self.panel,
                  panel.isVisible else { return }

            let windowFrame = panel.frame

            // Convert to screen coordinates if needed
            if !windowFrame.contains(NSEvent.mouseLocation) {
                Task { @MainActor in
                    self.hide()
                }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    deinit {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
