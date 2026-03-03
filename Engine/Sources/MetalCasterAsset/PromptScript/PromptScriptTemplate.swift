import Foundation

/// Data stored in a `.prompt` file (serialized as JSON).
public struct PromptScriptData: Codable, Sendable, Equatable {
    public var name: String
    public var initialState: String
    public var perFrameBehavior: String
    public var publicInterface: String
    public var customFields: [CustomField]

    public struct CustomField: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var label: String
        public var content: String

        public init(id: UUID = UUID(), label: String = "", content: String = "") {
            self.id = id
            self.label = label
            self.content = content
        }
    }

    public init(
        name: String = "",
        initialState: String = "",
        perFrameBehavior: String = "",
        publicInterface: String = "",
        customFields: [CustomField] = []
    ) {
        self.name = name
        self.initialState = initialState
        self.perFrameBehavior = perFrameBehavior
        self.publicInterface = publicInterface
        self.customFields = customFields
    }

    public var swiftIdentifier: String {
        name.replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Whether the three required fields have content.
    public var isComplete: Bool {
        !swiftIdentifier.isEmpty
            && !initialState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !perFrameBehavior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !publicInterface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Status of a prompt script compilation.
public enum PromptCompileStatus: Sendable, Equatable {
    case idle
    case compiling
    case success
    case failed(String)
}

/// Utilities for `.prompt` file management.
public struct PromptScriptTemplate {

    public static let fileExtension = "prompt"
    public static let generatedDirectoryName = ".generated"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    /// Creates a new `.prompt` file with the given name pre-filled.
    public static func generate(name: String) -> Data {
        let data = PromptScriptData(name: name)
        return (try? encoder.encode(data)) ?? Data()
    }

    /// Reads a `.prompt` file from disk.
    public static func load(from url: URL) throws -> PromptScriptData {
        let raw = try Data(contentsOf: url)
        return try decoder.decode(PromptScriptData.self, from: raw)
    }

    /// Writes a `.prompt` file to disk.
    public static func save(_ data: PromptScriptData, to url: URL) throws {
        let raw = try encoder.encode(data)
        try raw.write(to: url, options: .atomic)
    }

    /// Returns the expected generated Swift filename for a given prompt name.
    public static func generatedSwiftFilename(for promptName: String) -> String {
        let sanitized = promptName.replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
        return "\(sanitized).swift"
    }
}
