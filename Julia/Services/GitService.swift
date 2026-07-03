import Foundation

/// Resolves git info for pane working directories by reading repository
/// files directly — no `git` subprocess, so it's cheap enough to run for
/// every window on each palette refresh.
enum GitService {
    /// Returns the checked-out branch for the repository containing `path`,
    /// walking up parent directories to find the repository root. Returns a
    /// short commit hash for a detached HEAD, nil outside any repository.
    static func currentBranch(forDirectory path: String) -> String? {
        guard let gitDir = findGitDir(startingAt: path),
              let head = try? String(contentsOf: gitDir.appending(path: "HEAD"), encoding: .utf8)
        else { return nil }

        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let refPrefix = "ref: refs/heads/"
        if trimmed.hasPrefix(refPrefix) {
            return String(trimmed.dropFirst(refPrefix.count))
        }
        // Detached HEAD: the file holds a raw commit hash.
        return trimmed.count >= 7 ? String(trimmed.prefix(7)) : nil
    }

    /// Locates the effective git directory for `path`. Handles both regular
    /// repositories (`.git` directory) and worktrees/submodules, where `.git`
    /// is a file containing "gitdir: <actual location>".
    private static func findGitDir(startingAt path: String) -> URL? {
        var dir = URL(filePath: path).standardizedFileURL
        // Walk up by component count: deletingLastPathComponent() never
        // converges at the root (it produces "/..", "/../..", …), so a
        // parent-equality check would loop forever.
        while dir.pathComponents.count > 1 {
            let dotGit = dir.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit.path(percentEncoded: false), isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return dotGit
                }
                // Worktree or submodule: ".git" is a pointer file.
                let gitdirPrefix = "gitdir:"
                guard let firstLine = (try? String(contentsOf: dotGit, encoding: .utf8))?
                          .split(separator: "\n").first.map(String.init),
                      firstLine.hasPrefix(gitdirPrefix)
                else { return nil }
                let target = String(firstLine.dropFirst(gitdirPrefix.count))
                    .trimmingCharacters(in: .whitespaces)
                return URL(filePath: target, relativeTo: dir).standardizedFileURL
            }
            dir = dir.deletingLastPathComponent().standardizedFileURL
        }
        return nil
    }
}
