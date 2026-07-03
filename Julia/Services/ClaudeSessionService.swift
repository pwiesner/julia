import Foundation

/// Infers what the Claude Code session in a given directory is doing by
/// reading its transcript. Claude Code appends every message to
/// `~/.claude/projects/<encoded-cwd>/<session>.jsonl`, so the most recent
/// user/assistant entry says whether it's mid-turn or waiting for the user.
enum ClaudeSessionService {
    static func activity(forDirectory path: String) -> ClaudeActivity? {
        guard let transcript = newestTranscript(forDirectory: path),
              let entry = lastConversationEntry(in: transcript) else { return nil }

        switch entry.type {
        case "user":
            // A user message or tool result was just appended; Claude is
            // processing it.
            return .working
        case "assistant":
            // A tool call means the turn continues; plain text ends it.
            return entry.hasToolUse ? .working : .waitingForInput
        default:
            return nil
        }
    }

    // MARK: - Transcript discovery

    /// Claude Code names project directories by replacing every
    /// non-alphanumeric character of the working directory with "-".
    private static func newestTranscript(forDirectory path: String) -> URL? {
        let encoded = path.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let dir = URL.homeDirectory.appending(path: ".claude/projects/\(encoded)")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files
            .filter { $0.pathExtension == "jsonl" }
            .max { modificationDate($0) < modificationDate($1) }
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    // MARK: - Transcript parsing

    private struct Entry {
        let type: String
        let hasToolUse: Bool
    }

    /// Returns the most recent user/assistant entry, skipping housekeeping
    /// records ("system", "permission-mode", "ai-title", ...). Reads only
    /// the file's tail; transcripts grow to many megabytes.
    private static func lastConversationEntry(in url: URL) -> Entry? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let chunkSize: UInt64 = 256 * 1024
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > chunkSize ? size - chunkSize : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        // Lossy decode: the chunk may start mid-character or mid-line, and
        // that partial first line fails JSON parsing anyway.
        let text = String(decoding: data, as: UTF8.self)

        for line in text.split(separator: "\n").reversed() {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "user" || type == "assistant" else { continue }
            let content = (json["message"] as? [String: Any])?["content"]
            let hasToolUse = (content as? [[String: Any]])?
                .contains { $0["type"] as? String == "tool_use" } ?? false
            return Entry(type: type, hasToolUse: hasToolUse)
        }
        return nil
    }
}
