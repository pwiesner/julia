import Foundation

/// State of a Claude Code session, from beeper hooks (exact) or pane
/// classification (fallback).
enum ClaudeActivity: Sendable, Hashable {
    /// Claude is processing a message or running tools.
    case working
    /// Claude finished its turn and is waiting for the user.
    case waitingForInput
    /// Claude is blocked mid-task waiting for permission to run a tool.
    case waitingForPermission
}
