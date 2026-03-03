import Foundation

/// A single property discovered from a Component struct.
public struct ScriptProperty: Sendable, Equatable {
    public let name: String
    public let type: String
    public let defaultValue: String

    public init(name: String, type: String, defaultValue: String) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
    }
}

/// Discovered gameplay script entry from source scanning.
public struct GameplayScriptEntry: Sendable, Equatable {
    public let className: String
    public let componentName: String?
    public let sourceURL: URL
    public let properties: [ScriptProperty]

    public init(className: String, componentName: String?, sourceURL: URL, properties: [ScriptProperty] = []) {
        self.className = className
        self.componentName = componentName
        self.sourceURL = sourceURL
        self.properties = properties
    }

    /// Derives a short display name by stripping common suffixes.
    public var displayName: String {
        if let comp = componentName {
            return comp.replacingOccurrences(of: "Component", with: "")
        }
        return className.replacingOccurrences(of: "System", with: "")
            .replacingOccurrences(of: "Script", with: "")
    }
}

/// Scans `.swift` files for gameplay System and Component declarations.
///
/// Detects patterns like:
/// - `class FooSystem: GameplayScript`  /  `class FooSystem: System`
/// - `struct FooComponent: Component`
/// and pairs them by filename so the build system knows which types to instantiate.
public struct GameplayScriptScanner {

    public init() {}

    /// Scans one or more directories for `.swift` files and extracts script entries.
    public func scan(directories: [URL]) -> [GameplayScriptEntry] {
        let fm = FileManager.default
        var entries: [GameplayScriptEntry] = []

        for dir in directories {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "swift" else { continue }
                guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

                let systems = extractSystems(from: source)
                let components = extractComponents(from: source)
                let propsMap = extractAllProperties(from: source)

                for systemName in systems {
                    let paired = components.first
                    let props = paired.flatMap { propsMap[$0] } ?? []
                    entries.append(GameplayScriptEntry(
                        className: systemName,
                        componentName: paired,
                        sourceURL: fileURL,
                        properties: props
                    ))
                }

                for comp in components where systems.isEmpty {
                    entries.append(GameplayScriptEntry(
                        className: "",
                        componentName: comp,
                        sourceURL: fileURL,
                        properties: propsMap[comp] ?? []
                    ))
                }
            }
        }

        return entries
    }

    /// Extracts all unique script display names (suitable for the inspector picker).
    public func scriptNames(in directories: [URL]) -> [String] {
        let entries = scan(directories: directories)
        var names: [String] = []
        var seen = Set<String>()
        for e in entries where !e.className.isEmpty {
            let name = e.displayName
            if seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names.sorted()
    }

    /// Returns the discovered properties for a script with the given display name.
    public func properties(forScript name: String, in directories: [URL]) -> [ScriptProperty] {
        let entries = scan(directories: directories)
        return entries.first(where: { $0.displayName == name })?.properties ?? []
    }

    // MARK: - Regex Helpers

    private let systemPattern = try! NSRegularExpression(
        pattern: #"(?:class|struct)\s+(\w+)\s*:\s*(?:\w+\s*,\s*)*(?:GameplayScript|System)\b"#
    )

    private let componentPattern = try! NSRegularExpression(
        pattern: #"(?:struct|class)\s+(\w+)\s*:\s*(?:\w+\s*,\s*)*Component\b"#
    )

    /// Matches `public var name: Type = default` or `var name: Type = default`
    private let propertyPattern = try! NSRegularExpression(
        pattern: #"(?:public\s+)?var\s+(\w+)\s*:\s*([^\s=]+)\s*=\s*(.+)"#
    )

    private func extractSystems(from source: String) -> [String] {
        extract(pattern: systemPattern, from: source)
    }

    private func extractComponents(from source: String) -> [String] {
        extract(pattern: componentPattern, from: source)
    }

    private func extract(pattern: NSRegularExpression, from source: String) -> [String] {
        let range = NSRange(source.startIndex..., in: source)
        return pattern.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[r])
        }
    }

    /// Extracts stored properties for each Component struct found in source.
    private func extractAllProperties(from source: String) -> [String: [ScriptProperty]] {
        var result: [String: [ScriptProperty]] = [:]
        let components = extractComponents(from: source)
        guard !components.isEmpty else { return result }

        let lines = source.components(separatedBy: .newlines)
        for compName in components {
            let headerPattern = try! NSRegularExpression(
                pattern: #"(?:struct|class)\s+\#(NSRegularExpression.escapedPattern(for: compName))\s*:"#
            )
            guard let headerIdx = lines.firstIndex(where: { line in
                let range = NSRange(line.startIndex..., in: line)
                return headerPattern.firstMatch(in: line, range: range) != nil
            }) else { continue }

            var props: [ScriptProperty] = []
            var braceDepth = 0
            var started = false
            for i in headerIdx..<lines.count {
                let line = lines[i]
                for ch in line {
                    if ch == "{" { braceDepth += 1; started = true }
                    if ch == "}" { braceDepth -= 1 }
                }
                if started && braceDepth <= 0 { break }

                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("public init") || trimmed.hasPrefix("init") { continue }

                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if let match = propertyPattern.firstMatch(in: trimmed, range: range),
                   match.numberOfRanges >= 4,
                   let nameRange = Range(match.range(at: 1), in: trimmed),
                   let typeRange = Range(match.range(at: 2), in: trimmed),
                   let defaultRange = Range(match.range(at: 3), in: trimmed) {
                    let propName = String(trimmed[nameRange])
                    let propType = String(trimmed[typeRange])
                    let propDefault = String(trimmed[defaultRange]).trimmingCharacters(in: .whitespaces)
                    props.append(ScriptProperty(name: propName, type: propType, defaultValue: propDefault))
                }
            }
            result[compName] = props
        }
        return result
    }
}
