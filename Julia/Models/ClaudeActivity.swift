import Foundation

/// Coarse state of a Claude Code session, derived from its transcript.
enum ClaudeActivity: Sendable {
    /// Claude is processing a message or running tools.
    case working
    /// Claude finished its turn and is waiting for the user.
    case waitingForInput
}
