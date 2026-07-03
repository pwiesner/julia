import Foundation

/// Classifies what a Claude Code session is doing from its pane content.
/// The footer Claude Code draws is the source of truth: a spinner line like
/// "· Architecting… (2m 11s · ↓ 6.2k tokens)" or "esc to interrupt" renders
/// while a turn runs, and permission prompts render "Do you want to
/// proceed?". Transcript files can't distinguish a running tool from a
/// permission prompt, so the pane is more reliable than the transcript.
enum ClaudeSessionService {
    /// Claude Code chrome visible at an idle prompt (the permission-mode
    /// indicator line). Seeing it without a spinner means the session is
    /// waiting for the user.
    private static let idleChromeMarkers = [
        "shift+tab to cycle",
        "accept edits on",
        "plan mode on",
        "bypass permissions on"
    ]

    static func activity(fromPaneText text: String) -> ClaudeActivity? {
        // Only inspect the footer region: conversation text above it can
        // quote any of these markers.
        let footer = text.split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(15)
            .map { $0.lowercased() }

        if footer.contains(where: { $0.contains("do you want to proceed") }) {
            return .waitingForInput
        }
        if footer.contains(where: { $0.contains("esc to interrupt") || isSpinnerLine($0) }) {
            return .working
        }
        if footer.contains(where: { line in idleChromeMarkers.contains { line.contains($0) } }) {
            return .waitingForInput
        }
        return nil
    }

    /// Matches the activity spinner: a glyph, a gerund, an ellipsis, then
    /// elapsed time — "· architecting… (2m 11s · …)" (already lowercased).
    private static func isSpinnerLine(_ line: String) -> Bool {
        line.range(of: #"^\s*\S{1,2} [a-z]+… \(\d"#, options: .regularExpression) != nil
    }
}
