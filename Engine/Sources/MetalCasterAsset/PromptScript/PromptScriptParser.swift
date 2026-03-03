import Foundation

/// Validates `.prompt` data before compilation.
public struct PromptScriptValidator {

    public static func validate(_ data: PromptScriptData) -> [String] {
        var errors: [String] = []

        if data.swiftIdentifier.isEmpty {
            errors.append("Name must contain at least one letter or digit")
        }
        if data.initialState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Initial State is required")
        }
        if data.perFrameBehavior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Per-Frame Behavior is required")
        }
        if data.publicInterface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Public Interface is required")
        }

        return errors
    }
}
