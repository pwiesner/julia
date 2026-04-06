import AppKit
import SwiftUI

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
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        setupClickOutsideMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        removeClickOutsideMonitor()
    }

    func toggle<Content: View>(content: Content) {
        if isVisible {
            hide()
        } else {
            show(content: content)
        }
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
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
