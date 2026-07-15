import AppKit

/// Locates and raises the terminal app hosting the user's tmux client.
/// julia only ever talks to the tmux server, so it never learns the
/// terminal by name; walking the attached client's process ancestry
/// finds whatever GUI app owns it — Terminal, iTerm, Ghostty, kitty —
/// without hardcoding any of them.
@MainActor
enum TerminalFocusService {
    static func activateTerminal(hostingClientPid pid: Int) {
        guard let app = hostApp(forClientPid: pid) else { return }
        // Cooperative activation: a plain activate() from an app that
        // isn't frontmost is silently ignored, and julia never is — it's
        // a background agent. The notification click or hotkey just gave
        // julia the user's attention; claim it, then hand the activation
        // to the terminal.
        NSApp.activate()
        app.activate(from: .current, options: [.activateAllWindows])
    }

    /// Whether the terminal hosting the tmux client is the frontmost
    /// app — the difference between "on this window, watching it" and
    /// "on this window, behind Chrome".
    static func isTerminalFrontmost(hostingClientPid pid: Int) -> Bool {
        guard let host = hostApp(forClientPid: pid),
              let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        return host.processIdentifier == frontmost.processIdentifier
    }

    private static func hostApp(forClientPid pid: Int) -> NSRunningApplication? {
        var current = pid_t(pid)
        // Walk parents until a real GUI app owns the process; give up
        // after a few hops rather than climbing into launchd.
        for _ in 0..<10 {
            if let app = NSRunningApplication(processIdentifier: current),
               app.activationPolicy == .regular {
                return app
            }
            let parent = parentPid(of: current)
            guard parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    private static func parentPid(of pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return pid_t(info.pbi_ppid)
    }
}
