import Foundation

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

    init(type: TmuxCommandType, argument: String? = nil, targetSession: String? = nil) {
        self.type = type
        self.argument = argument
        self.targetSession = targetSession
    }
}

struct PaletteItem: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let icon: String
    let action: PaletteAction

    enum PaletteAction: Sendable {
        case switchSession(String)
        case switchWindow(sessionName: String, windowIndex: Int)
        case command(TmuxCommandType)
        case executeCommand(TmuxCommand)
    }
}
