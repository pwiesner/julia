import AppKit
import os

/// Locates and raises the terminal app hosting the user's tmux client.
/// julia only ever talks to the tmux server, so it never learns the
/// terminal by name; walking the attached client's process ancestry
/// finds whatever GUI app owns it — Terminal, iTerm, Ghostty, kitty —
/// without hardcoding any of them.
@MainActor
enum TerminalFocusService {
    private nonisolated static let log = Logger(
        subsystem: "com.pwiesner.julia", category: "terminal-focus"
    )

    static func activateTerminal(hostingClientPid pid: Int?) {
        guard let pid else {
            log.error("raise: no attached tmux client")
            return
        }
        guard let app = hostApp(forClientPid: pid) else {
            log.error("raise: no GUI app in ancestry of client pid \(pid)")
            return
        }
        log.info("raise: \(app.localizedName ?? "?", privacy: .public) pid \(app.processIdentifier)")
        // Not activate(): cooperative activation only honors apps the
        // user just touched, and julia's grant — a notification click —
        // kept expiring during the tmux round-trips (worked in testing,
        // died in daily use). LaunchServices doesn't care who asks:
        // "opening" an already-running app just activates it, the same
        // way `open -a Terminal` raises it from any shell.
        guard let bundleURL = app.bundleURL else {
            // Unbundled terminal (a raw binary): all we have is the
            // attention-gated path.
            log.info("raise: unbundled binary, attention-gated fallback")
            NSApp.activate()
            app.activate(from: .current, options: [.activateAllWindows])
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if let error {
                log.error("raise: openApplication failed: \(error.localizedDescription, privacy: .public)")
            }
            // Whether activation actually stuck, not just returned.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "none"
                log.info("raise: frontmost after 600ms: \(front, privacy: .public)")
            }
        }
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

    /// sysctl, not proc_pidinfo: the ancestry passes through
    /// /usr/bin/login, which is root-owned, and proc_pidinfo answers
    /// EPERM for root processes when asked by a user process. sysctl
    /// exposes the same basic info ps shows, for every process.
    private static func parentPid(of pid: pid_t) -> pid_t {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else {
            log.error("walk: sysctl(\(pid)) failed, errno \(errno)")
            return 0
        }
        return info.kp_eproc.e_ppid
    }
}
