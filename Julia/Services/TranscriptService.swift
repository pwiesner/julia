import Foundation

/// Answers "what is this agent actually doing?" from a Claude Code
/// transcript: the most recent human prompt, flattened to one line, for
/// display next to the agent's state.
///
/// Claude Code appends one JSONL entry per event. Only the file's tail is
/// searched — transcripts grow to many megabytes and the palette
/// re-resolves on every hook event — and results are cached by
/// modification time, so an unchanged transcript costs one stat.
actor TranscriptService {
    private var cache: [String: (mtime: Date, task: String?)] = [:]

    /// How much of the file tail to search. Big enough to reach back past
    /// the tool results that follow a prompt, small enough to stay cheap.
    /// A prompt buried deeper than this is simply not found.
    private static let tailBytes: UInt64 = 256 * 1024

    func currentTask(transcriptPath: String) -> String? {
        let url = URL(filePath: transcriptPath)
        guard let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate else { return nil }
        if let cached = cache[transcriptPath], cached.mtime == mtime {
            return cached.task
        }
        let task = Self.lastHumanPrompt(in: url)
        cache[transcriptPath] = (mtime, task)
        return task
    }

    private static func lastHumanPrompt(in url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > tailBytes ? size - tailBytes : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        var lines = data.split(separator: UInt8(ascii: "\n"))
        // Seeking mid-file lands mid-line; the first fragment isn't JSON.
        if offset > 0, !lines.isEmpty { lines.removeFirst() }

        for line in lines.reversed() {
            if let prompt = humanPrompt(fromLine: Data(line)) { return prompt }
        }
        return nil
    }

    /// The prompt text if this entry is a real human turn. Transcripts
    /// record much else under type "user": subagent traffic (isSidechain),
    /// injected context (isMeta), tool results, and tag-wrapped entries
    /// like slash-command invocations, system reminders, and interrupt
    /// notices — none of which are the task.
    private static func humanPrompt(fromLine line: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "user",
              object["isSidechain"] as? Bool != true,
              object["isMeta"] as? Bool != true,
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
