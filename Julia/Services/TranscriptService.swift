import Foundation

/// Answers "what is this agent actually doing?" from a Claude Code
/// transcript: the most recent human prompt (the task) and the current
/// context footprint, for display next to the agent's state.
///
/// Claude Code appends one JSONL entry per event. Only the file's tail is
/// searched — transcripts grow to many megabytes and the palette
/// re-resolves on every hook event — and results are cached by
/// modification time, so an unchanged transcript costs one stat.
actor TranscriptService {
    /// What the tail of a transcript says about its session.
    struct Summary: Sendable, Equatable {
        /// The most recent human prompt, flattened to one line.
        var task: String?
        /// Tokens occupying the model's context as of the last reply:
        /// the input side of its usage (prompt + cache reads + cache
        /// writes). The window size isn't recorded, so this stays a raw
        /// count rather than a guessed-denominator percentage.
        var contextTokens: Int?
    }

    private var cache: [String: (mtime: Date, summary: Summary)] = [:]

    /// How much of the file tail to search. Big enough to reach back past
    /// the tool results that follow a prompt, small enough to stay cheap.
    /// A prompt buried deeper than this is simply not found.
    private static let tailBytes: UInt64 = 256 * 1024

    func summary(transcriptPath: String) -> Summary {
        let url = URL(filePath: transcriptPath)
        guard let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate else { return Summary() }
        if let cached = cache[transcriptPath], cached.mtime == mtime {
            return cached.summary
        }
        let summary = Self.summarize(url)
        cache[transcriptPath] = (mtime, summary)
        return summary
    }

    private static func summarize(_ url: URL) -> Summary {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Summary() }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return Summary() }
        let offset = size > tailBytes ? size - tailBytes : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return Summary() }

        var lines = data.split(separator: UInt8(ascii: "\n"))
        // Seeking mid-file lands mid-line; the first fragment isn't JSON.
        if offset > 0, !lines.isEmpty { lines.removeFirst() }

        var summary = Summary()
        for line in lines.reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["isSidechain"] as? Bool != true else { continue }
            switch object["type"] as? String {
            case "user" where summary.task == nil:
                summary.task = humanPrompt(from: object)
            case "assistant" where summary.contextTokens == nil:
                summary.contextTokens = contextTokens(from: object)
            default:
                break
            }
            if summary.task != nil, summary.contextTokens != nil { break }
        }
        return summary
    }

    /// The prompt text if this entry is a real human turn. Transcripts
    /// record much else under type "user": injected context (isMeta),
    /// tool results, and tag-wrapped entries like slash-command
    /// invocations, system reminders, and interrupt notices — none of
    /// which are the task.
    private static func humanPrompt(from object: [String: Any]) -> String? {
        guard object["isMeta"] as? Bool != true,
              let message = object["message"] as? [String: Any] else { return nil }

        let text: String
        if let string = message["content"] as? String {
            text = string
        } else if let parts = message["content"] as? [[String: Any]] {
            text = parts
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: " ")
        } else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<"), !trimmed.hasPrefix("[") else { return nil }
        return oneLine(trimmed)
    }

    /// Context occupancy from a reply's usage block. Error placeholders
    /// and other syntheticized entries carry no usage and report nil.
    private static func contextTokens(from object: [String: Any]) -> Int? {
        guard let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return nil }
        let total = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
            .compactMap { usage[$0] as? Int }
            .reduce(0, +)
        return total > 0 ? total : nil
    }

    /// Row subtitles get one line; collapse whitespace and cap the length,
    /// leaving finer truncation to the view.
    private static func oneLine(_ text: String) -> String {
        let flattened = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard flattened.count > 120 else { return flattened }
        return flattened.prefix(120).trimmingCharacters(in: .whitespaces) + "…"
    }
}
