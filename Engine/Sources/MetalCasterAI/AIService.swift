import Foundation

/// Thread-safe AI service that handles communication with LLM APIs.
public actor AIService {

    public static let shared = AIService()

    private let session = URLSession.shared

    // MARK: - Agent Tool Chat

    /// General-purpose LLM call for the agent system. Sends conversation messages
    /// with a custom system prompt and returns the raw LLM text response.
    /// The caller (MCAgent) is responsible for parsing tool calls from the response.
    public func agentToolChat(
        messages: [ChatMessage],
        systemPrompt: String,
        settings: AISettings
    ) async throws -> String {
        switch settings.selectedProvider {
        case .openai:   return try await callOpenAI(system: systemPrompt, messages: messages, settings: settings)
        case .anthropic: return try await callAnthropic(system: systemPrompt, messages: messages, settings: settings)
        case .gemini:   return try await callGemini(system: systemPrompt, messages: messages, settings: settings)
        }
    }

    // MARK: - Legacy Shader Agent Chat

    public func agentChat(messages: [ChatMessage], context: String, dataFlowDescription: String, settings: AISettings) async throws -> AgentResponse {
        let systemPrompt = """
        You are a Metal Shading Language (MSL) expert assistant embedded in a real-time shader editor app.
        You are an intelligent Agent that can directly add new shader layers or modify existing ones in the user's workspace.

        RESPONSE FORMAT: You MUST respond with ONLY a valid JSON object. No markdown fences, no extra text.
        {
          "canFulfill": true/false,
          "explanation": "Your explanation to the user (same language as user)",
          "actions": [
            {
              "type": "addLayer",
              "category": "vertex|fragment|fullscreen",
              "name": "Descriptive Layer Name",
              "code": "complete compilable MSL code"
            }
          ],
          "barriers": ["technical barrier 1", "barrier 2"]
        }
        Set "barriers" to null when canFulfill is true. Set "actions" to [] when no layer changes are needed.
        For modifying existing layers, use type "modifyLayer" with additional field "targetLayerName".

        CURRENT WORKSPACE:
        \(context)

        DATA FLOW CONFIGURATION:
        \(dataFlowDescription)

        SHADER CODE RULES:
        Vertex & Fragment shaders: DO NOT include #include, using namespace metal, or struct definitions.
        Entry: vertex_main / fragment_main. Uniforms at buffer(1).
        Fullscreen: MUST be self-contained with #include, struct definitions, BOTH vertex_main and fragment_main.
        User parameters: // @param _name type default [min max]

        IMPORTANT:
        - All generated shader code MUST compile.
        - Answer in the SAME LANGUAGE the user writes in.
        - Be concise in explanations.
        """
        let rawResponse: String
        switch settings.selectedProvider {
        case .openai:   rawResponse = try await callOpenAI(system: systemPrompt, messages: messages, settings: settings)
        case .anthropic: rawResponse = try await callAnthropic(system: systemPrompt, messages: messages, settings: settings)
        case .gemini:   rawResponse = try await callGemini(system: systemPrompt, messages: messages, settings: settings)
        }
        do {
            return try parseAgentResponse(from: rawResponse)
        } catch {
            return AgentResponse.plainText(rawResponse)
        }
    }

    public func generateTutorial(topic: String, settings: AISettings) async throws -> [TutorialStep] {
        let systemPrompt = """
        You are a Metal Shading Language expert educator. Generate a step-by-step shader tutorial.
        Output ONLY a valid JSON array (no markdown). Each element:
        { "title","subtitle","instructions","goal","hint","category":"fragment|vertex|fullscreen","starterCode","solutionCode" }
        All shaders must compile. Include #include <metal_stdlib> and using namespace metal.
        Generate 3-6 progressive steps.
        """
        let userMsg = ChatMessage(role: .user, content: "Create a tutorial about: \(topic)")
        let response: String
        switch settings.selectedProvider {
        case .openai:   response = try await callOpenAI(system: systemPrompt, messages: [userMsg], settings: settings)
        case .anthropic: response = try await callAnthropic(system: systemPrompt, messages: [userMsg], settings: settings)
        case .gemini:   response = try await callGemini(system: systemPrompt, messages: [userMsg], settings: settings)
        }
        return try parseTutorialSteps(from: response)
    }

    // MARK: - Provider Implementations

    private func callOpenAI(system: String, messages: [ChatMessage], settings: AISettings) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(settings.openAIKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var msgs: [[String: String]] = [["role": "system", "content": system]]
        for m in messages { msgs.append(["role": m.role == .user ? "user" : "assistant", "content": m.content]) }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": settings.openAIModel, "messages": msgs, "max_tokens": 4096] as [String: Any])
        let (data, resp) = try await session.data(for: req)
        try check(resp, data: data, provider: "OpenAI")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]], let msg = choices.first?["message"] as? [String: Any], let content = msg["content"] as? String else { throw AIError.invalidResponse("OpenAI") }
        return content
    }

    private func callAnthropic(system: String, messages: [ChatMessage], settings: AISettings) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(settings.anthropicKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var msgs: [[String: String]] = []
        for m in messages { msgs.append(["role": m.role == .user ? "user" : "assistant", "content": m.content]) }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": settings.anthropicModel, "max_tokens": 4096, "system": system, "messages": msgs] as [String: Any])
        let (data, resp) = try await session.data(for: req)
        try check(resp, data: data, provider: "Anthropic")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]], let text = content.first?["text"] as? String else { throw AIError.invalidResponse("Anthropic") }
        return text
    }

    private func callGemini(system: String, messages: [ChatMessage], settings: AISettings) async throws -> String {
        let model = settings.geminiModel
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(settings.geminiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var contents: [[String: Any]] = []
        for m in messages { contents.append(["role": m.role == .user ? "user" : "model", "parts": [["text": m.content]]]) }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["contents": contents, "systemInstruction": ["parts": [["text": system]]]] as [String: Any])
        let (data, resp) = try await session.data(for: req)
        try check(resp, data: data, provider: "Gemini")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let cands = json?["candidates"] as? [[String: Any]], let co = cands.first?["content"] as? [String: Any], let parts = co["parts"] as? [[String: Any]], let text = parts.first?["text"] as? String else { throw AIError.invalidResponse("Gemini") }
        return text
    }

    // MARK: - Helpers

    private func check(_ response: URLResponse, data: Data, provider: String) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError(provider: provider, status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: body)
        }
    }

    private func parseTutorialSteps(from text: String) throws -> [TutorialStep] {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = s.range(of: "["), let b = s.range(of: "]", options: .backwards) { s = String(s[a.lowerBound...b.upperBound]) }
        guard let data = s.data(using: .utf8), let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw AIError.invalidResponse("parse") }
        var steps: [TutorialStep] = []
        for (i, item) in arr.enumerated() {
            guard let title = item["title"] as? String, let sub = item["subtitle"] as? String,
                  let inst = item["instructions"] as? String, let goal = item["goal"] as? String,
                  let hint = item["hint"] as? String, let catStr = item["category"] as? String,
                  let starter = item["starterCode"] as? String, let solution = item["solutionCode"] as? String else { continue }
            steps.append(TutorialStep(id: i, title: title, subtitle: sub, instructions: inst, goal: goal, hint: hint, category: catStr, starterCode: starter, solutionCode: solution))
        }
        guard !steps.isEmpty else { throw AIError.invalidResponse("0 steps") }
        return steps
    }

    private func parseAgentResponse(from text: String) throws -> AgentResponse {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fencePattern = #"```(?:json)?\s*([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: fencePattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned) {
            cleaned = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let startIdx = cleaned.firstIndex(of: "{") else {
            throw AIError.invalidResponse("No JSON object found in agent response")
        }
        var depth = 0
        var inString = false
        var escaped = false
        var endIdx = cleaned.endIndex
        for i in cleaned.indices[startIdx...] {
            let c = cleaned[i]
            if escaped { escaped = false; continue }
            if c == "\\" && inString { escaped = true; continue }
            if c == "\"" { inString.toggle(); continue }
            if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { endIdx = cleaned.index(after: i); break }
                }
            }
        }
        let jsonString = String(cleaned[startIdx..<endIdx])
        guard let data = jsonString.data(using: .utf8) else {
            throw AIError.invalidResponse("Failed to encode agent JSON to data")
        }
        return try JSONDecoder().decode(AgentResponse.self, from: data)
    }
}
