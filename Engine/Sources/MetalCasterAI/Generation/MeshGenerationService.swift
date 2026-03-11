import Foundation

// MARK: - Mesh Generation Protocol

/// Abstraction for image-to-3D and text-to-3D mesh generation services (Tripo3D, Meshy, etc.)
public protocol MeshGenerationService: Sendable {
    var providerName: String { get }
    func generateFromImage(imageData: Data, options: MeshGenOptions) async throws -> GeneratedMesh
    func generateFromText(prompt: String, options: MeshGenOptions) async throws -> GeneratedMesh
}

/// Options for mesh generation.
public struct MeshGenOptions: Codable, Sendable {
    public var style: MeshStyle
    public var format: MeshOutputFormat
    public var generatePBR: Bool
    public var targetPolyCount: Int?

    public init(
        style: MeshStyle = .realistic,
        format: MeshOutputFormat = .glb,
        generatePBR: Bool = true,
        targetPolyCount: Int? = nil
    ) {
        self.style = style
        self.format = format
        self.generatePBR = generatePBR
        self.targetPolyCount = targetPolyCount
    }
}

public enum MeshStyle: String, Codable, Sendable, CaseIterable {
    case realistic = "Realistic"
    case stylized  = "Stylized"
    case lowpoly   = "Low Poly"
    case cartoon   = "Cartoon"
    case clay      = "Clay"
    case steampunk = "Steampunk"
}

public enum MeshOutputFormat: String, Codable, Sendable, CaseIterable {
    case glb  = "glb"
    case obj  = "obj"
    case fbx  = "fbx"
    case usdz = "usdz"
    case stl  = "stl"
}

/// Result of a mesh generation request.
public struct GeneratedMesh: Sendable {
    public let meshData: Data
    public let format: MeshOutputFormat
    public let prompt: String
    public let provider: String
    public let polyCount: Int?
    public let hasTextures: Bool

    public init(meshData: Data, format: MeshOutputFormat, prompt: String,
                provider: String, polyCount: Int? = nil, hasTextures: Bool = false) {
        self.meshData = meshData
        self.format = format
        self.prompt = prompt
        self.provider = provider
        self.polyCount = polyCount
        self.hasTextures = hasTextures
    }

    /// Writes the mesh data to a temporary file and returns its URL.
    public func writeToTempFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "mc_generated_\(UUID().uuidString).\(format.rawValue)"
        let url = tempDir.appendingPathComponent(filename)
        try meshData.write(to: url)
        return url
    }
}

// MARK: - Tripo3D Implementation

/// Tripo3D v3.0 mesh generation via REST API.
public final class Tripo3DService: MeshGenerationService, @unchecked Sendable {
    public let providerName = "Tripo3D v3.0"
    private let apiKey: String
    private let baseURL: String

    public init(apiKey: String, baseURL: String = "https://api.tripo3d.ai/v2") {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func generateFromImage(imageData: Data, options: MeshGenOptions) async throws -> GeneratedMesh {
        let taskID = try await createImageTask(imageData: imageData, options: options)
        return try await pollForResult(taskID: taskID, prompt: "[image]", options: options)
    }

    public func generateFromText(prompt: String, options: MeshGenOptions) async throws -> GeneratedMesh {
        let taskID = try await createTextTask(prompt: prompt, options: options)
        return try await pollForResult(taskID: taskID, prompt: prompt, options: options)
    }

    private func createTextTask(prompt: String, options: MeshGenOptions) async throws -> String {
        let body: [String: Any] = [
            "type": "text_to_model",
            "prompt": prompt,
            "model_version": "v3.0",
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: URL(string: "\(baseURL)/openapi/task")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GenerationError.apiError("Tripo3D create task failed")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let taskData = json["data"] as? [String: Any],
              let taskID = taskData["task_id"] as? String else {
            throw GenerationError.parseError("Failed to parse Tripo3D task response")
        }

        return taskID
    }

    private func createImageTask(imageData: Data, options: MeshGenOptions) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "\(baseURL)/openapi/task")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"type\"\r\n\r\n".data(using: .utf8)!)
        body.append("image_to_model\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"input.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GenerationError.apiError("Tripo3D image task creation failed")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let taskData = json["data"] as? [String: Any],
              let taskID = taskData["task_id"] as? String else {
            throw GenerationError.parseError("Failed to parse Tripo3D image task response")
        }

        return taskID
    }

    private func pollForResult(taskID: String, prompt: String, options: MeshGenOptions) async throws -> GeneratedMesh {
        for _ in 0..<120 {
            try await Task.sleep(nanoseconds: 2_000_000_000)

            var request = URLRequest(url: URL(string: "\(baseURL)/openapi/task/\(taskID)")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let taskData = json["data"] as? [String: Any],
                  let status = taskData["status"] as? String else { continue }

            if status == "success" {
                guard let output = taskData["output"] as? [String: Any],
                      let modelURLString = output["model"] as? String,
                      let modelURL = URL(string: modelURLString) else {
                    throw GenerationError.parseError("No model URL in Tripo3D response")
                }

                let (meshData, _) = try await URLSession.shared.data(from: modelURL)
                return GeneratedMesh(
                    meshData: meshData,
                    format: .glb,
                    prompt: prompt,
                    provider: providerName,
                    hasTextures: true
                )
            } else if status == "failed" {
                throw GenerationError.apiError("Tripo3D generation failed")
            }
        }

        throw GenerationError.apiError("Tripo3D generation timed out")
    }
}

// MARK: - Meshy Implementation

/// Meshy API mesh generation service.
public final class MeshyService: MeshGenerationService, @unchecked Sendable {
    public let providerName = "Meshy"
    private let apiKey: String
    private let baseURL: String

    public init(apiKey: String, baseURL: String = "https://api.meshy.ai/v2") {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func generateFromImage(imageData: Data, options: MeshGenOptions) async throws -> GeneratedMesh {
        throw GenerationError.notConfigured("Meshy image-to-3D requires uploading image first. Use text-to-3D instead.")
    }

    public func generateFromText(prompt: String, options: MeshGenOptions) async throws -> GeneratedMesh {
        let body: [String: Any] = [
            "mode": "preview",
            "prompt": prompt,
            "art_style": options.style.rawValue,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: URL(string: "\(baseURL)/text-to-3d")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 202 else {
            throw GenerationError.apiError("Meshy text-to-3D creation failed")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let taskID = json["result"] as? String else {
            throw GenerationError.parseError("Failed to parse Meshy task response")
        }

        for _ in 0..<120 {
            try await Task.sleep(nanoseconds: 3_000_000_000)

            var pollRequest = URLRequest(url: URL(string: "\(baseURL)/text-to-3d/\(taskID)")!)
            pollRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (pollData, _) = try await URLSession.shared.data(for: pollRequest)
            guard let pollJSON = try JSONSerialization.jsonObject(with: pollData) as? [String: Any],
                  let status = pollJSON["status"] as? String else { continue }

            if status == "SUCCEEDED" {
                guard let modelURLs = pollJSON["model_urls"] as? [String: Any],
                      let glbURL = modelURLs["glb"] as? String,
                      let meshURL = URL(string: glbURL) else {
                    throw GenerationError.parseError("No GLB URL in Meshy response")
                }

                let (meshData, _) = try await URLSession.shared.data(from: meshURL)
                return GeneratedMesh(
                    meshData: meshData,
                    format: .glb,
                    prompt: prompt,
                    provider: providerName,
                    hasTextures: true
                )
            } else if status == "FAILED" {
                throw GenerationError.apiError("Meshy generation failed")
            }
        }

        throw GenerationError.apiError("Meshy generation timed out")
    }
}

// MARK: - Generation Manager

/// Coordinates text-to-image and image-to-3D pipelines.
@Observable
public final class AssetGenerationManager {
    public var imageService: (any ImageGenerationService)?
    public var meshService: (any MeshGenerationService)?
    public var isGenerating: Bool = false
    public var lastError: String?

    public init() {}

    /// Full pipeline: text -> image -> 3D mesh. Returns a file URL to the generated mesh.
    public func generateAsset(prompt: String, style: ImageStyle = .realistic) async throws -> URL {
        guard let imgService = imageService else {
            throw GenerationError.notConfigured("Image generation service not configured. Set API key in AI Settings.")
        }
        guard let meshSvc = meshService else {
            throw GenerationError.notConfigured("Mesh generation service not configured. Set API key in AI Settings.")
        }

        isGenerating = true
        defer { isGenerating = false }

        let image = try await imgService.generate(prompt: prompt, width: 1024, height: 1024, style: style)
        let mesh = try await meshSvc.generateFromImage(imageData: image.imageData, options: MeshGenOptions(style: .realistic))
        return try mesh.writeToTempFile()
    }

    /// Text-to-3D directly (bypasses image generation).
    public func generateMeshFromText(prompt: String, style: MeshStyle = .realistic) async throws -> URL {
        guard let meshSvc = meshService else {
            throw GenerationError.notConfigured("Mesh generation service not configured.")
        }

        isGenerating = true
        defer { isGenerating = false }

        let mesh = try await meshSvc.generateFromText(prompt: prompt, options: MeshGenOptions(style: style))
        return try mesh.writeToTempFile()
    }
}
