import Foundation

/// Schema definition for a tool that an agent can invoke via LLM function calling.
public struct AgentToolDefinition: Codable, Sendable, Identifiable {
    public let name: String
    public let description: String
    public let parameters: [ToolParameter]

    public var id: String { name }

    public init(name: String, description: String, parameters: [ToolParameter]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    /// Renders this tool as human-readable text for inclusion in LLM system prompts.
    public var promptDescription: String {
        var lines = ["### \(name)", description, "Parameters:"]
        for p in parameters {
            let req = p.required ? "required" : "optional"
            var line = "  - \(p.name) (\(p.type.rawValue), \(req)): \(p.description)"
            if let vals = p.enumValues, !vals.isEmpty {
                line += " [values: \(vals.joined(separator: ", "))]"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

/// A single parameter in a tool's invocation schema.
public struct ToolParameter: Codable, Sendable {
    public let name: String
    public let type: ParameterType
    public let description: String
    public let required: Bool
    public let enumValues: [String]?

    public init(name: String, type: ParameterType, description: String, required: Bool = true, enumValues: [String]? = nil) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.enumValues = enumValues
    }

    public enum ParameterType: String, Codable, Sendable {
        case string
        case number
        case integer
        case boolean
        case array
        case object
    }
}

/// A request from the LLM to execute a specific tool with arguments.
public struct ToolCallRequest: Codable, Sendable {
    public let tool: String
    public let arguments: [String: JSONValue]

    public init(tool: String, arguments: [String: JSONValue]) {
        self.tool = tool
        self.arguments = arguments
    }
}

/// Type-erased JSON value for passing tool arguments.
public enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .boolean(b)
        } else if let i = try? container.decode(Int.self) {
            self = .integer(i)
        } else if let d = try? container.decode(Double.self) {
            self = .number(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):  try container.encode(s)
        case .number(let d):  try container.encode(d)
        case .integer(let i): try container.encode(i)
        case .boolean(let b): try container.encode(b)
        case .array(let a):   try container.encode(a)
        case .object(let o):  try container.encode(o)
        case .null:           try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var numberValue: Double? {
        switch self {
        case .number(let d):  return d
        case .integer(let i): return Double(i)
        default: return nil
        }
    }

    public var intValue: Int? {
        if case .integer(let i) = self { return i }
        if case .number(let d) = self { return Int(d) }
        return nil
    }

    public var boolValue: Bool? {
        if case .boolean(let b) = self { return b }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Convenience: extract a Float array (e.g. for positions [x, y, z]).
    public var floatArray: [Float]? {
        guard let arr = arrayValue else { return nil }
        return arr.compactMap { $0.numberValue.map { Float($0) } }
    }
}

/// Result of executing a tool call against the engine.
public struct ToolResult: Codable, Sendable {
    public let toolName: String
    public let success: Bool
    public let output: String

    public init(toolName: String, success: Bool, output: String) {
        self.toolName = toolName
        self.success = success
        self.output = output
    }
}
