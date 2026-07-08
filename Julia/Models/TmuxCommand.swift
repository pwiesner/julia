import SwiftUI

enum TmuxCommandType: String, CaseIterable, Sendable {
    case switchSession = "switch"
    case newSession = "new"
    case renameSession = "rename"
    case killSession = "kill"
    case moveWindow = "move"
    case newWindow = "window"
    case renameWindow = "rename-window"

    var displayName: String {
        switch self {
        case .switchSession: "Switch to session"
        case .newSession: "New session"
        case .renameSession: "Rename session"
        case .killSession: "Kill session"
        case .moveWindow: "Move window to session"
        case .newWindow: "New window"
        case .renameWindow: "Rename window"
        }
    }

    var icon: String {
        switch self {
        case .switchSession: "arrow.right.circle"
        case .newSession: "plus.circle"
        case .renameSession: "pencil.circle"
        case .killSession: "xmark.circle"
        case .moveWindow: "arrow.up.and.down.and.arrow.left.and.right"
        case .newWindow: "macwindow.badge.plus"
        case .renameWindow: "pencil"
        }
    }

    var requiresArgument: Bool {
        switch self {
        case .switchSession, .newSession, .renameSession, .killSession, .moveWindow, .renameWindow:
            true
        case .newWindow:
            false
        }
    }
}

struct TmuxCommand: Identifiable, Sendable {
    let id = UUID()
    let type: TmuxCommandType
    let argument: String?
    let targetSession: String?
    /// Starting directory for commands that create things. Julia's own
    /// cwd is "/" when launched from Finder — never a sane inheritance.
    let workingDirectory: String?

    var displayText: String {
        switch type {
        case .switchSession:
            if let arg = argument {
                "Switch to \(arg)"
            } else {
                type.displayName
            }
        case .newSession:
            if let arg = argument {
                "New session: \(arg)"
            } else {
                type.displayName
            }
        case .renameSession:
            if let arg = argument, let target = targetSession {
                "Rename \(target) to \(arg)"
            } else if let arg = argument {
                "Rename session to \(arg)"
            } else {
                type.displayName
            }
        case .killSession:
            if let arg = argument {
                "Kill session: \(arg)"
            } else {
                type.displayName
            }
        case .moveWindow:
            if let arg = argument {
                "Move window to \(arg)"
            } else {
                type.displayName
            }
        case .newWindow:
            type.displayName
        case .renameWindow:
            if let arg = argument {
                "Rename window to \(arg)"
            } else {
                type.displayName
            }
        }
    }

    init(
        type: TmuxCommandType,
        argument: String? = nil,
        targetSession: String? = nil,
        workingDirectory: String? = nil
    ) {
        self.type = type
        self.argument = argument
        self.targetSession = targetSession
        self.workingDirectory = workingDirectory
    }
}

struct PaletteItem: Identifiable, Sendable {
    /// Stable across rebuilds — items are recomputed on every refresh,
    /// and identity that survives lets SwiftUI animate a row moving
    /// instead of treating it as a new stranger.
    var id: String {
        switch action {
        case .switchSession(let name): "session:\(name)"
        case .switchWindow(let sessionName, let windowIndex): "window:\(sessionName):\(windowIndex)"
        case .command(let type): "command:\(type.rawValue)"
        case .executeCommand: "execute:\(title)"
        case .showWindows: "screen:windows"
        case .showAgents: "screen:agents"
        case .showTidy: "screen:tidy"
        case .showHelp: "screen:help"
        }
    }

    let title: String
    let subtitle: String?
    let icon: String
    var iconColor: Color? = nil
    /// When set, a section header with this title renders above the row.
    var sectionTitle: String? = nil
    /// Stale rows render dimmed until hovered or selected.
    var isStale: Bool = false
    /// Rows that create things activate only via shift-return or an
    /// explicit click — plain return must never conjure a session out
    /// of a typo (see the graveyard of sessions named "13").
    var requiresShiftEnter: Bool = false
    /// Dimmed context beside the title, e.g. the branch ("⎇ main").
    var titleAccessory: String? = nil
    /// The single context line under the title; see `Detail`.
    var detail: Detail? = nil
    /// Right-aligned metric, e.g. "asked 4m ago".
    var trailingPrimary: String? = nil
    /// Smaller metric beneath it, e.g. "76K ctx".
    var trailingSecondary: String? = nil
    let action: PaletteAction

    /// One line of context per row — whichever matters most right now.
    /// Kind picks the rendering: asks demand attention, tasks read as
    /// quotes, plain is quiet plumbing.
    struct Detail: Sendable {
        enum Kind: Sendable {
            case ask
            case task
            case plain
        }

        let kind: Kind
        let text: String
    }

    enum PaletteAction: Sendable {
        case switchSession(String)
        case switchWindow(sessionName: String, windowIndex: Int)
        case command(TmuxCommandType)
        case executeCommand(TmuxCommand)
        case showWindows
        case showAgents
        case showTidy
        case showHelp
    }
}
