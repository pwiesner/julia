import Foundation

/// Feeds native tmux switches into the visit history. Julia otherwise
/// only sees jumps made through its own palette, so the frecency model
/// drifts from reality all day. Tmux hooks (installed at launch,
/// idempotently) append every window selection to a log file this
/// service watches — the beeper pattern: instant updates, no polling.
///
/// Ingestion is chain-aware: a stop shorter than the chain window that
/// is immediately followed by another switch was hallway, not a
/// destination — flip-flip-flip hunting must not pollute the ranking,
/// while a purposeful quick visit (kill a service, rerun it) outlasts
/// the window and counts in full. Echoes of julia's own jumps (the
/// hooks fire for those too) are dropped so palette jumps don't count
/// twice.
@MainActor
final class VisitIngestService {
    private let history: VisitHistoryService
    private let tmuxService = TmuxService()

    private static let directory = URL.homeDirectory.appending(path: ".local/state/julia")
    private static let logURL = directory.appending(path: "visits.log")
    /// Below this, an immediately-abandoned stop is pass-through.
    private static let chainWindow: TimeInterval = 2

    private var source: (any DispatchSourceFileSystemObject)?
    private var offset: UInt64 = 0
    private var pending: (windowId: String, sessionId: String, at: Date)?
    private var commitTask: Task<Void, Never>?

    init(history: VisitHistoryService) {
        self.history = history
    }

    func start() {
        let path = Self.logURL.path(percentEncoded: false)
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        // Skip anything appended while julia wasn't running: replaying
        // stale visits as if fresh would distort the ranking's recency.
        offset = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0

        Task {
            try? await tmuxService.installVisitHooks(logPath: path)
        }
        watch()
    }

    func stop() {
        source?.cancel()
        source = nil
        commitTask?.cancel()
    }

    private func watch() {
        let descriptor = open(Self.logURL.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.drain()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    /// Reads whatever the hooks appended since the last drain.
    private func drain() {
        guard let handle = try? FileHandle(forReadingFrom: Self.logURL) else { return }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return }
        if size < offset { offset = 0 }  // file was truncated or replaced
        guard size > offset, (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return }
        offset = size

        for line in text.split(separator: "\n") {
            // "@12 $3 1783290000" — window id, session id, epoch seconds.
            let parts = line.split(separator: " ")
            guard parts.count >= 3,
                  parts[0].hasPrefix("@"),
                  let epoch = TimeInterval(parts[2]) else { continue }
            ingest(
                windowId: String(parts[0]),
                sessionId: String(parts[1]),
                at: Date(timeIntervalSince1970: epoch)
            )
        }
    }

    private func ingest(windowId: String, sessionId: String, at date: Date) {
        // This switch ends the previous stop; commit it if it survived
        // long enough to have been a destination.
        resolvePending(before: date)

        // Julia already recorded its own jump directly; the hook echo
        // would double-count it and bias the ranking toward palette use.
        guard !history.recordedRecently(id: windowId, within: Self.chainWindow) else { return }

        pending = (windowId, sessionId, date)
        scheduleCommit()
    }

    private func resolvePending(before date: Date) {
        if let pending, date.timeIntervalSince(pending.at) >= Self.chainWindow {
            commit(pending)
        }
        pending = nil
    }

    /// The final stop of a chain has no follow-up switch to resolve it;
    /// a timer commits it once it outlives the chain window.
    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.chainWindow))
            guard !Task.isCancelled, let self, let pending = self.pending else { return }
            self.commit(pending)
            self.pending = nil
        }
    }

    private func commit(_ visit: (windowId: String, sessionId: String, at: Date)) {
        history.recordVisit(id: visit.windowId, at: visit.at)
        history.recordVisit(id: visit.sessionId, at: visit.at)
    }
}
