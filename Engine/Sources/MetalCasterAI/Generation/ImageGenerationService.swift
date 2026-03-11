import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Image Generation Protocol

/// Abstraction for text-to-image generation services (FLUX.2, DALL-E, etc.)
public protocol ImageGenerationService: Sendable {
    var providerName: String { get }
    func generate(prompt: String, width: Int, height: Int, style: ImageStyle?) async throws -> GeneratedImage
}

/// Style presets for image generation.
public enum ImageStyle: String, Codable, Sendable, CaseIterable {
    case realistic     = "Realistic"
    case stylized      = "Stylized"
    case lowpoly       = "Low Poly"
    case cartoon       = "Cartoon"
    case photographic  = "Photographic"
    case concept       = "Concept Art"
}

/// Result of an image generation request.
public struct GeneratedImage: Sendable {
    public let imageData: Data
    public let width: Int
    public let height: Int
    public let prompt: String
    public let provider: String

    public init(imageData: Data, width: Int, height: Int, prompt: String, provider: String) {
        self.imageData = imageData
        self.width = width
        self.height = height
        self.prompt = prompt
        self.provider = provider
    }
}

// MARK: - FLUX.2 Implementation

/// FLUX.2 Pro text-to-image generation via REST API.
public final class Flux2ImageService: ImageGenerationService, @unchecked Sendable {
    public let providerName = "FLUX.2 Pro"
    private let apiKey: String
    private let baseURL: String

    public init(apiKey: String, baseURL: String = "https://api.bfl.ai/v1") {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func generate(prompt: String, width: Int, height: Int, style: ImageStyle?) async throws -> GeneratedImage {
        let styledPrompt: String
        if let style = style {
            styledPrompt = "\(prompt), \(style.rawValue.lowercased()) style, high quality, detailed"
        } else {
            styledPrompt = prompt
        }

        let body: [String: Any] = [
            "prompt": styledPrompt,
            "width": width,
            "height": height,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: URL(string: "\(baseURL)/flux-2-pro")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GenerationError.apiError("FLUX.2 API returned non-200 status")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let imageURLString = json["url"] as? String ?? json["image_url"] as? String,
              let imageURL = URL(string: imageURLString) else {
            throw GenerationError.parseError("Failed to parse FLUX.2 response")
        }

        let (imageData, _) = try await URLSession.shared.data(from: imageURL)

        return GeneratedImage(
            imageData: imageData,
            width: width,
            height: height,
            prompt: styledPrompt,
            provider: providerName
        )
    }
}

// MARK: - Generation Errors

public enum GenerationError: Error, Sendable {
    case apiError(String)
    case parseError(String)
    case networkError(String)
    case invalidInput(String)
    case notConfigured(String)
}
