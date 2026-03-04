import Foundation
import os.log

// MARK: - Log Level

public enum MCLogLevel: Int, Comparable, Sendable, CaseIterable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case fatal = 4

    public static func < (lhs: MCLogLevel, rhs: MCLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .debug:   return "DEBUG"
        case .info:    return "INFO"
        case .warning: return "WARN"
        case .error:   return "ERROR"
        case .fatal:   return "FATAL"
        }
    }

    public var icon: String {
        switch self {
        case .debug:   return "circle"
        case .info:    return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        case .fatal:   return "xmark.octagon.fill"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .debug:   return .debug
        case .info:    return .info
        case .warning: return .default
        case .error:   return .error
        case .fatal:   return .fault
        }
    }
}

// MARK: - Log Subsystem

public enum MCLogSubsystem: String, Sendable, CaseIterable {
    case core     = "Core"
    case renderer = "Renderer"
    case physics  = "Physics"
    case audio    = "Audio"
    case ecs      = "ECS"
    case asset    = "Asset"
    case input    = "Input"
    case ai       = "AI"
    case scene    = "Scene"
    case editor   = "Editor"
    case general  = "General"
}

// MARK: - Log Entry

public struct MCLogEntry: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: MCLogLevel
    public let subsystem: MCLogSubsystem
    public let message: String
    public let file: String
    public let line: Int
    public let frameCount: UInt64
    public let callStack: [String]?

    public static func == (lhs: MCLogEntry, rhs: MCLogEntry) -> Bool {
        lhs.id == rhs.id
    }

    public var formattedMessage: String {
        let time = Self.timestampFormatter.string(from: timestamp)
        let fileName = (file as NSString).lastPathComponent
        return "[\(time)] [\(level.label)] [\(subsystem.rawValue)] \(message) (\(fileName):\(line))"
    }

    public var shortMessage: String {
        "[\(level.label)] [\(subsystem.rawValue)] \(message)"
    }

    public var compactTime: String {
        Self.compactFormatter.string(from: timestamp)
    }

    /// Grouping key for collapsing consecutive identical messages.
    public var collapseKey: String {
        "\(level.rawValue)|\(subsystem.rawValue)|\(message)"
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let compactFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// MARK: - Log Event (for EventBus integration)

public struct MCLogEvent: MCEvent {
    public let entry: MCLogEntry
}

// MARK: - MCLog

public final class MCLog: @unchecked Sendable {

    public static let shared = MCLog()

    public var minimumLevel: MCLogLevel = .debug
    public var enabledSubsystems: Set<MCLogSubsystem> = Set(MCLogSubsystem.allCases)
    public var useOSLog: Bool = true

    /// External event bus reference. Set by Engine on startup to broadcast log events.
    public weak var eventBus: EventBus?

    /// Current frame count, updated by Engine each tick.
    public var currentFrameCount: UInt64 = 0

    /// Monotonically increasing counter — poll this to detect new log entries.
    public var revision: Int {
        lock.lock()
        defer { lock.unlock() }
        return _revision
    }

    private let lock = NSLock()
    private var buffer: [MCLogEntry] = []
    private let maxBufferSize = 2048
    private var _revision: Int = 0

    private let osLogger: os.Logger

    private static let callStackSkipFrames = 3

    private init() {
        osLogger = os.Logger(subsystem: "com.metalcaster.engine", category: "MCLog")
        buffer.reserveCapacity(maxBufferSize)
    }

    // MARK: - Public API

    public static func debug(_ subsystem: MCLogSubsystem, _ message: @autoclosure () -> String,
                             file: String = #file, line: Int = #line) {
        #if DEBUG
        shared.log(.debug, subsystem, message(), file: file, line: line)
        #endif
    }

    public static func info(_ subsystem: MCLogSubsystem, _ message: @autoclosure () -> String,
                            file: String = #file, line: Int = #line) {
        shared.log(.info, subsystem, message(), file: file, line: line)
    }

    public static func warning(_ subsystem: MCLogSubsystem, _ message: @autoclosure () -> String,
                               file: String = #file, line: Int = #line) {
        shared.log(.warning, subsystem, message(), file: file, line: line)
    }

    public static func error(_ subsystem: MCLogSubsystem, _ message: @autoclosure () -> String,
                             file: String = #file, line: Int = #line) {
        shared.log(.error, subsystem, message(), file: file, line: line)
    }

    public static func fatal(_ subsystem: MCLogSubsystem, _ message: @autoclosure () -> String,
                             file: String = #file, line: Int = #line) {
        shared.log(.fatal, subsystem, message(), file: file, line: line)
    }

    /// Measures the execution time of a block and logs the duration.
    @discardableResult
    public static func measure<T>(_ subsystem: MCLogSubsystem, _ label: String,
                                  file: String = #file, line: Int = #line,
                                  block: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        shared.log(.debug, subsystem, "\(label): \(String(format: "%.2f", elapsed))ms", file: file, line: line)
        return result
    }

    // MARK: - Buffer Access

    /// Returns a snapshot of recent log entries. Thread-safe.
    public func recentEntries(count: Int = 256) -> [MCLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        let start = max(0, buffer.count - count)
        return Array(buffer[start...])
    }

    /// Returns entries filtered by level and/or subsystem.
    public func filteredEntries(level: MCLogLevel? = nil, subsystem: MCLogSubsystem? = nil,
                                count: Int = 256) -> [MCLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        var result = buffer
        if let level { result = result.filter { $0.level >= level } }
        if let subsystem { result = result.filter { $0.subsystem == subsystem } }
        let start = max(0, result.count - count)
        return Array(result[start...])
    }

    /// Clears all buffered log entries.
    public func clearBuffer() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
        _revision += 1
    }

    /// Returns counts grouped by severity category: (info, warning, error).
    /// info includes `.debug` and `.info`; error includes `.error` and `.fatal`.
    public func counts() -> (info: Int, warning: Int, error: Int) {
        lock.lock()
        defer { lock.unlock() }
        var i = 0, w = 0, e = 0
        for entry in buffer {
            switch entry.level {
            case .debug, .info: i += 1
            case .warning:      w += 1
            case .error, .fatal: e += 1
            }
        }
        return (i, w, e)
    }

    // MARK: - Internal

    private func log(_ level: MCLogLevel, _ subsystem: MCLogSubsystem, _ message: String,
                     file: String, line: Int) {
        guard level >= minimumLevel, enabledSubsystems.contains(subsystem) else { return }

        let stack: [String]? = (level >= .error)
            ? Array(Thread.callStackSymbols.dropFirst(Self.callStackSkipFrames))
            : nil

        let entry = MCLogEntry(
            id: UUID(),
            timestamp: Date(),
            level: level,
            subsystem: subsystem,
            message: message,
            file: file,
            line: line,
            frameCount: currentFrameCount,
            callStack: stack
        )

        lock.lock()
        if buffer.count >= maxBufferSize {
            buffer.removeFirst(maxBufferSize / 4)
        }
        buffer.append(entry)
        _revision += 1
        lock.unlock()

        if useOSLog {
            osLogger.log(level: level.osLogType, "\(entry.formattedMessage, privacy: .public)")
        }

        eventBus?.publishImmediate(MCLogEvent(entry: entry))
    }
}
