import Foundation

/// Identifies the functional specialization of an agent within the engine.
public enum AgentRole: String, CaseIterable, Codable, Sendable, Identifiable {
    case render   = "Render"
    case scene    = "Scene"
    case shader   = "Shader"
    case asset    = "Asset"
    case optimize = "Optimize"
    case analyze  = "Analyze"
    case art      = "Art"
    case audio    = "Audio"
    case composer = "Composer"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .render:   return "Render"
        case .scene:    return "Scene"
        case .shader:   return "Shader"
        case .asset:    return "Asset"
        case .optimize: return "Optimize"
        case .analyze:  return "Analyze"
        case .art:      return "Art"
        case .audio:    return "Audio"
        case .composer: return "Composer"
        }
    }

    public var icon: String {
        switch self {
        case .render:   return "paintbrush.pointed"
        case .scene:    return "cube.transparent"
        case .shader:   return "function"
        case .asset:    return "folder"
        case .optimize: return "gauge.with.dots.needle.67percent"
        case .analyze:  return "waveform.path.ecg"
        case .art:      return "paintpalette"
        case .audio:    return "speaker.wave.3"
        case .composer: return "mountain.2"
        }
    }

    public var tagline: String {
        switch self {
        case .render:   return "Rendering pipeline, lighting, post-processing"
        case .scene:    return "Entity lifecycle, hierarchy, transforms"
        case .shader:   return "MSL authoring, materials, shader debugging"
        case .asset:    return "Asset pipeline, import/export, bundling"
        case .optimize: return "Performance profiling, GPU analysis"
        case .analyze:  return "Scene diagnostics, error detection"
        case .art:      return "Visual style, color palettes, composition"
        case .audio:    return "Spatial audio, buses, sound design"
        case .composer: return "Terrain generation, scene composition, AI-driven world building"
        }
    }
}

/// Runtime lifecycle state of an agent.
public enum AgentStatus: String, Codable, Sendable {
    case idle       = "Idle"
    case thinking   = "Thinking"
    case executing  = "Executing"
    case error      = "Error"
}
