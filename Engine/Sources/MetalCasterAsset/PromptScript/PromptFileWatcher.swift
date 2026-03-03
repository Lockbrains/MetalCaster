import Foundation

/// Watches a directory for `.prompt` file changes using DispatchSource,
/// with debouncing to avoid redundant compilations during rapid edits.
public final class PromptFileWatcher: @unchecked Sendable {

    /// Called when a `.prompt` file has been modified (after debounce).
    /// The URL is the path to the changed `.prompt` file.
    public var onPromptChanged: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var watchedDirectory: URL?
    private var knownHashes: [URL: Int] = [:]
    private let debounceInterval: TimeInterval
    private var debounceWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.metalcaster.prompt-watcher", qos: .utility)

    public init(debounceInterval: TimeInterval = 2.0) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        stopWatching()
    }

    /// Begins watching the given directory for `.prompt` file modifications.
    public func startWatching(directory: URL) {
        stopWatching()
        watchedDirectory = directory
        snapshotPromptFiles(in: directory)

        fileDescriptor = open(directory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("[PromptFileWatcher] Failed to open directory: \(directory.path)")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .extend],
            queue: queue
        )

        src.setEventHandler { [weak self] in
            self?.scheduleCheck()
        }

        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        source = src
        src.resume()
        print("[PromptFileWatcher] Watching: \(directory.path)")
    }

    /// Stops watching the directory.
    public func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        source?.cancel()
        source = nil
        watchedDirectory = nil
        knownHashes.removeAll()
    }

    /// Forces an immediate check for changed `.prompt` files.
    public func forceCheck() {
        queue.async { [weak self] in
            self?.checkForChanges()
        }
    }

    // MARK: - Private

    private func scheduleCheck() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.checkForChanges()
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func checkForChanges() {
        guard let dir = watchedDirectory else { return }
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let promptFiles = contents.filter { $0.pathExtension.lowercased() == "prompt" }

        for url in promptFiles {
            let hash = fileContentHash(url)
            let previousHash = knownHashes[url]

            if previousHash == nil {
                knownHashes[url] = hash
                continue
            }

            if hash != previousHash {
                knownHashes[url] = hash
                DispatchQueue.main.async { [weak self] in
                    self?.onPromptChanged?(url)
                }
            }
        }

        let currentURLs = Set(promptFiles)
        for tracked in knownHashes.keys where !currentURLs.contains(tracked) {
            knownHashes.removeValue(forKey: tracked)
        }
    }

    private func snapshotPromptFiles(in directory: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents where url.pathExtension.lowercased() == "prompt" {
            knownHashes[url] = fileContentHash(url)
        }
    }

    private func fileContentHash(_ url: URL) -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        return data.hashValue
    }
}
