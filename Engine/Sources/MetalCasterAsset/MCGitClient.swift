import Foundation

/// Represents the status of a file in a git working tree.
public enum GitFileStatusKind: String, Sendable {
    case modified    = "M"
    case added       = "A"
    case deleted     = "D"
    case renamed     = "R"
    case untracked   = "?"
    case ignored     = "!"
    case copied      = "C"
    case unmerged    = "U"
}

/// A single file's git status.
public struct GitFileStatus: Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let status: GitFileStatusKind
    public let isStaged: Bool

    public init(path: String, status: GitFileStatusKind, isStaged: Bool) {
        self.path = path
        self.status = status
        self.isStaged = isStaged
    }
}

/// A single git commit entry.
public struct GitCommit: Sendable, Identifiable {
    public var id: String { hash }
    public let hash: String
    public let shortHash: String
    public let author: String
    public let date: String
    public let message: String

    public init(hash: String, shortHash: String, author: String, date: String, message: String) {
        self.hash = hash
        self.shortHash = shortHash
        self.author = author
        self.date = date
        self.message = message
    }
}

/// A git branch reference.
public struct GitBranch: Sendable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let isCurrent: Bool
    public let isRemote: Bool

    public init(name: String, isCurrent: Bool, isRemote: Bool = false) {
        self.name = name
        self.isCurrent = isCurrent
        self.isRemote = isRemote
    }
}

/// Result of a diff operation.
public struct GitDiff: Sendable {
    public let filePath: String
    public let hunks: [DiffHunk]

    public struct DiffHunk: Sendable {
        public let header: String
        public let lines: [DiffLine]
    }

    public struct DiffLine: Sendable {
        public enum Kind: Sendable { case context, addition, deletion }
        public let kind: Kind
        public let content: String
    }
}

/// Git CLI wrapper. Executes git commands via `Process` against a working directory.
///
/// This client requires `git` to be installed on the host system.
/// It is designed for non-sandboxed SPM targets; App Store sandboxed apps
/// cannot spawn subprocesses. A future version may use libgit2 bindings.
public final class MCGitClient: @unchecked Sendable {

    public let workingDirectory: URL

    /// Whether git is available on this system.
    public private(set) var isGitAvailable: Bool = false

    /// Whether the working directory is inside a git repository.
    public private(set) var isRepository: Bool = false

    public init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
        self.isGitAvailable = checkGitAvailable()
        if isGitAvailable {
            self.isRepository = checkIsRepository()
        }
    }

    // MARK: - Repository Init

    /// Initializes a new git repository in the working directory.
    @discardableResult
    public func initRepository() -> Bool {
        guard isGitAvailable else { return false }
        let result = run(["init"])
        if result.exitCode == 0 {
            isRepository = true
        }
        return result.exitCode == 0
    }

    // MARK: - Status

    /// Returns the list of changed files in the working tree.
    public func status() -> [GitFileStatus] {
        guard isRepository else { return [] }
        let result = run(["status", "--porcelain=v1"])
        guard result.exitCode == 0 else { return [] }

        return result.output
            .components(separatedBy: .newlines)
            .compactMap { line -> GitFileStatus? in
                guard line.count >= 3 else { return nil }
                let indexChar = line[line.startIndex]
                let workChar = line[line.index(after: line.startIndex)]
                let path = String(line.dropFirst(3))

                if indexChar == "?" && workChar == "?" {
                    return GitFileStatus(path: path, status: .untracked, isStaged: false)
                }
                if indexChar == "!" {
                    return GitFileStatus(path: path, status: .ignored, isStaged: false)
                }

                let staged = indexChar != " " && indexChar != "?"
                let statusChar = staged ? indexChar : workChar
                let kind: GitFileStatusKind
                switch statusChar {
                case "M": kind = .modified
                case "A": kind = .added
                case "D": kind = .deleted
                case "R": kind = .renamed
                case "C": kind = .copied
                case "U": kind = .unmerged
                default:  kind = .modified
                }

                return GitFileStatus(path: path, status: kind, isStaged: staged)
            }
    }

    // MARK: - Staging

    /// Stages a file for the next commit.
    @discardableResult
    public func add(_ path: String) -> Bool {
        run(["add", path]).exitCode == 0
    }

    /// Stages all changes.
    @discardableResult
    public func addAll() -> Bool {
        run(["add", "-A"]).exitCode == 0
    }

    /// Unstages a file.
    @discardableResult
    public func unstage(_ path: String) -> Bool {
        run(["restore", "--staged", path]).exitCode == 0
    }

    // MARK: - Commit

    /// Creates a commit with the given message.
    @discardableResult
    public func commit(message: String) -> Bool {
        run(["commit", "-m", message]).exitCode == 0
    }

    // MARK: - Log

    /// Returns recent commits (up to `limit`).
    public func log(limit: Int = 50) -> [GitCommit] {
        guard isRepository else { return [] }
        let format = "%H|%h|%an|%ci|%s"
        let result = run(["log", "--format=\(format)", "-n", "\(limit)"])
        guard result.exitCode == 0 else { return [] }

        return result.output
            .components(separatedBy: .newlines)
            .compactMap { line -> GitCommit? in
                let parts = line.split(separator: "|", maxSplits: 4).map(String.init)
                guard parts.count >= 5 else { return nil }
                return GitCommit(
                    hash: parts[0],
                    shortHash: parts[1],
                    author: parts[2],
                    date: parts[3],
                    message: parts[4]
                )
            }
    }

    // MARK: - Branches

    /// Lists all local and remote branches.
    public func branches() -> [GitBranch] {
        guard isRepository else { return [] }
        let result = run(["branch", "-a", "--no-color"])
        guard result.exitCode == 0 else { return [] }

        return result.output
            .components(separatedBy: .newlines)
            .compactMap { line -> GitBranch? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }

                let isCurrent = trimmed.hasPrefix("*")
                var name = isCurrent ? String(trimmed.dropFirst(2)) : trimmed
                let isRemote = name.hasPrefix("remotes/")
                if isRemote {
                    name = String(name.dropFirst("remotes/".count))
                }
                if name.contains("HEAD ->") { return nil }

                return GitBranch(name: name, isCurrent: isCurrent, isRemote: isRemote)
            }
    }

    /// Creates a new branch.
    @discardableResult
    public func createBranch(_ name: String) -> Bool {
        run(["branch", name]).exitCode == 0
    }

    /// Switches to a branch.
    @discardableResult
    public func checkout(_ branchName: String) -> Bool {
        run(["checkout", branchName]).exitCode == 0
    }

    /// The name of the current branch, or nil if detached HEAD.
    public var currentBranch: String? {
        let result = run(["rev-parse", "--abbrev-ref", "HEAD"])
        guard result.exitCode == 0 else { return nil }
        let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name == "HEAD" ? nil : name
    }

    // MARK: - Diff

    /// Returns the diff for a specific file (unstaged changes).
    public func diff(for path: String) -> String {
        let result = run(["diff", "--", path])
        return result.output
    }

    /// Returns the diff for a specific file (staged changes).
    public func diffStaged(for path: String) -> String {
        let result = run(["diff", "--cached", "--", path])
        return result.output
    }

    // MARK: - Remote

    /// Pushes the current branch to origin.
    @discardableResult
    public func push() -> Bool {
        run(["push"]).exitCode == 0
    }

    /// Pulls from origin for the current branch.
    @discardableResult
    public func pull() -> Bool {
        run(["pull"]).exitCode == 0
    }

    // MARK: - Discard

    /// Discards unstaged changes to a file.
    @discardableResult
    public func discardChanges(_ path: String) -> Bool {
        run(["checkout", "--", path]).exitCode == 0
    }

    // MARK: - Internal

    private struct ProcessResult {
        let output: String
        let exitCode: Int32
    }

    private func run(_ arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return ProcessResult(output: output, exitCode: process.terminationStatus)
        } catch {
            return ProcessResult(output: "", exitCode: -1)
        }
    }

    private func checkGitAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--version"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func checkIsRepository() -> Bool {
        run(["rev-parse", "--is-inside-work-tree"]).exitCode == 0
    }
}
