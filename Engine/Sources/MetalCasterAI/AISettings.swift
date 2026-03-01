import Foundation

/// Observable settings object that stores AI provider configuration.
/// Persists to UserDefaults.
@Observable
public class AISettings: @unchecked Sendable {
    public var selectedProvider: AIProvider {
        didSet { UserDefaults.standard.set(selectedProvider.rawValue, forKey: "ai_provider") }
    }
    public var openAIKey: String {
        didSet { UserDefaults.standard.set(openAIKey, forKey: "ai_openai_key") }
    }
    public var anthropicKey: String {
        didSet { UserDefaults.standard.set(anthropicKey, forKey: "ai_anthropic_key") }
    }
    public var geminiKey: String {
        didSet { UserDefaults.standard.set(geminiKey, forKey: "ai_gemini_key") }
    }
    public var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: "ai_openai_model") }
    }
    public var anthropicModel: String {
        didSet { UserDefaults.standard.set(anthropicModel, forKey: "ai_anthropic_model") }
    }
    public var geminiModel: String {
        didSet { UserDefaults.standard.set(geminiModel, forKey: "ai_gemini_model") }
    }

    public var currentKey: String {
        switch selectedProvider {
        case .openai: return openAIKey
        case .anthropic: return anthropicKey
        case .gemini: return geminiKey
        }
    }

    public var currentModel: String {
        switch selectedProvider {
        case .openai: return openAIModel
        case .anthropic: return anthropicModel
        case .gemini: return geminiModel
        }
    }

    public var isConfigured: Bool { !currentKey.isEmpty }

    public init() {
        let d = UserDefaults.standard
        self.selectedProvider = AIProvider(rawValue: d.string(forKey: "ai_provider") ?? "") ?? .openai
        self.openAIKey = d.string(forKey: "ai_openai_key") ?? ""
        self.anthropicKey = d.string(forKey: "ai_anthropic_key") ?? ""
        self.geminiKey = d.string(forKey: "ai_gemini_key") ?? ""
        self.openAIModel = d.string(forKey: "ai_openai_model") ?? AIProvider.openai.defaultModel
        self.anthropicModel = d.string(forKey: "ai_anthropic_model") ?? AIProvider.anthropic.defaultModel
        self.geminiModel = d.string(forKey: "ai_gemini_model") ?? AIProvider.gemini.defaultModel
    }
}
