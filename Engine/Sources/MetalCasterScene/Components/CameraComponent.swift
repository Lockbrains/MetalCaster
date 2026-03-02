import Foundation
import simd
import MetalCasterCore

// MARK: - Sensor Preset

public enum SensorPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case fullFrame    = "Full Frame"
    case super35      = "Super 35"
    case apsc         = "APS-C"
    case microFourThirds = "Micro 4/3"
    case custom       = "Custom"

    public var id: String { rawValue }

    /// Width x Height in millimeters.
    public var sensorSizeMM: SIMD2<Float> {
        switch self {
        case .fullFrame:       return SIMD2<Float>(36.0, 24.0)
        case .super35:         return SIMD2<Float>(24.89, 18.66)
        case .apsc:            return SIMD2<Float>(23.6, 15.6)
        case .microFourThirds: return SIMD2<Float>(17.3, 13.0)
        case .custom:          return SIMD2<Float>(36.0, 24.0)
        }
    }
}

// MARK: - Background Type

public enum CameraBackgroundType: String, CaseIterable, Codable, Sendable {
    case solidColor    = "Solid Color"
    case skybox        = "Skybox"
    case uninitialized = "Uninitialized"
}

// MARK: - Depth Texture Mode

public enum DepthTextureMode: String, CaseIterable, Codable, Sendable {
    case none         = "None"
    case depth        = "Depth"
    case depthNormals = "Depth + Normals"
}

// MARK: - Camera Component

/// Camera projection, physical properties, and rendering configuration.
public struct CameraComponent: Component {
    public enum Projection: String, Codable, Sendable, CaseIterable {
        case perspective
        case orthographic
    }

    // MARK: Base Properties

    public var projection: Projection
    public var fov: Float
    public var nearZ: Float
    public var farZ: Float
    public var orthoSize: Float
    public var isActive: Bool
    public var clearColor: SIMD4<Float>

    // MARK: Physical Camera

    public var usePhysicalProperties: Bool
    public var sensorPreset: SensorPreset
    public var customSensorSize: SIMD2<Float>
    public var focalLength: Float
    public var aperture: Float
    public var iso: Float
    public var shutterSpeed: Float
    public var focusDistance: Float
    public var shutterAngle: Float

    // MARK: Rendering Settings

    public var allowPostProcessing: Bool
    public var allowHDR: Bool
    public var backgroundType: CameraBackgroundType
    public var renderingPriority: Int
    public var depthTextureMode: DepthTextureMode

    // MARK: Init

    public init(
        projection: Projection = .perspective,
        fov: Float = Float.pi / 3.0,
        nearZ: Float = 0.1,
        farZ: Float = 1000.0,
        orthoSize: Float = 10.0,
        isActive: Bool = true,
        clearColor: SIMD4<Float> = SIMD4<Float>(0.15, 0.15, 0.15, 1.0),
        usePhysicalProperties: Bool = false,
        sensorPreset: SensorPreset = .fullFrame,
        customSensorSize: SIMD2<Float> = SIMD2<Float>(36.0, 24.0),
        focalLength: Float = 50.0,
        aperture: Float = 2.8,
        iso: Float = 200.0,
        shutterSpeed: Float = 1.0 / 125.0,
        focusDistance: Float = 10.0,
        shutterAngle: Float = 180.0,
        allowPostProcessing: Bool = true,
        allowHDR: Bool = true,
        backgroundType: CameraBackgroundType = .solidColor,
        renderingPriority: Int = 0,
        depthTextureMode: DepthTextureMode = .depth
    ) {
        self.projection = projection
        self.fov = fov
        self.nearZ = nearZ
        self.farZ = farZ
        self.orthoSize = orthoSize
        self.isActive = isActive
        self.clearColor = clearColor
        self.usePhysicalProperties = usePhysicalProperties
        self.sensorPreset = sensorPreset
        self.customSensorSize = customSensorSize
        self.focalLength = focalLength
        self.aperture = aperture
        self.iso = iso
        self.shutterSpeed = shutterSpeed
        self.focusDistance = focusDistance
        self.shutterAngle = shutterAngle
        self.allowPostProcessing = allowPostProcessing
        self.allowHDR = allowHDR
        self.backgroundType = backgroundType
        self.renderingPriority = renderingPriority
        self.depthTextureMode = depthTextureMode
    }

    // MARK: Computed (not serialized)

    public var sensorSizeMM: SIMD2<Float> {
        sensorPreset == .custom ? customSensorSize : sensorPreset.sensorSizeMM
    }

    /// Vertical FOV derived from physical sensor height and focal length.
    public var physicalFOV: Float {
        2.0 * atan(sensorSizeMM.y / (2.0 * focalLength))
    }

    /// The effective vertical FOV used for projection.
    public var effectiveFOV: Float {
        usePhysicalProperties ? physicalFOV : fov
    }

    /// EV100 exposure value: log2(N^2 / t) - log2(S / 100)
    public var ev100: Float {
        log2((aperture * aperture) / shutterSpeed) - log2(iso / 100.0)
    }

    /// Linear exposure multiplier derived from EV100.
    public var exposureMultiplier: Float {
        1.0 / (1.2 * pow(2.0, ev100))
    }

    /// Horizontal FOV derived from physical sensor width and focal length.
    public var physicalHorizontalFOV: Float {
        2.0 * atan(sensorSizeMM.x / (2.0 * focalLength))
    }

    // MARK: Codable customization for backward compat

    private enum CodingKeys: String, CodingKey {
        case projection, fov, nearZ, farZ, orthoSize, isActive, clearColor
        case usePhysicalProperties, sensorPreset, customSensorSize
        case focalLength, aperture, iso, shutterSpeed, focusDistance, shutterAngle
        case allowPostProcessing, allowHDR, backgroundType, renderingPriority, depthTextureMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        projection = try c.decodeIfPresent(Projection.self, forKey: .projection) ?? .perspective
        fov = try c.decodeIfPresent(Float.self, forKey: .fov) ?? (Float.pi / 3.0)
        nearZ = try c.decodeIfPresent(Float.self, forKey: .nearZ) ?? 0.1
        farZ = try c.decodeIfPresent(Float.self, forKey: .farZ) ?? 1000.0
        orthoSize = try c.decodeIfPresent(Float.self, forKey: .orthoSize) ?? 10.0
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        clearColor = try c.decodeIfPresent(SIMD4<Float>.self, forKey: .clearColor) ?? SIMD4<Float>(0.15, 0.15, 0.15, 1.0)

        usePhysicalProperties = try c.decodeIfPresent(Bool.self, forKey: .usePhysicalProperties) ?? false
        sensorPreset = try c.decodeIfPresent(SensorPreset.self, forKey: .sensorPreset) ?? .fullFrame
        customSensorSize = try c.decodeIfPresent(SIMD2<Float>.self, forKey: .customSensorSize) ?? SIMD2<Float>(36.0, 24.0)
        focalLength = try c.decodeIfPresent(Float.self, forKey: .focalLength) ?? 50.0
        aperture = try c.decodeIfPresent(Float.self, forKey: .aperture) ?? 2.8
        iso = try c.decodeIfPresent(Float.self, forKey: .iso) ?? 200.0
        shutterSpeed = try c.decodeIfPresent(Float.self, forKey: .shutterSpeed) ?? (1.0 / 125.0)
        focusDistance = try c.decodeIfPresent(Float.self, forKey: .focusDistance) ?? 10.0
        shutterAngle = try c.decodeIfPresent(Float.self, forKey: .shutterAngle) ?? 180.0

        allowPostProcessing = try c.decodeIfPresent(Bool.self, forKey: .allowPostProcessing) ?? true
        allowHDR = try c.decodeIfPresent(Bool.self, forKey: .allowHDR) ?? true
        backgroundType = try c.decodeIfPresent(CameraBackgroundType.self, forKey: .backgroundType) ?? .solidColor
        renderingPriority = try c.decodeIfPresent(Int.self, forKey: .renderingPriority) ?? 0
        depthTextureMode = try c.decodeIfPresent(DepthTextureMode.self, forKey: .depthTextureMode) ?? .depth
    }
}

// MARK: - Common Presets

extension CameraComponent {

    public static let commonFocalLengths: [Float] = [14, 24, 35, 50, 85, 135, 200]

    public static let commonApertures: [Float] = [1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0]

    public static let commonISOs: [Float] = [100, 200, 400, 800, 1600, 3200, 6400]

    public static let commonShutterSpeeds: [(label: String, value: Float)] = [
        ("1/8000", 1.0 / 8000.0),
        ("1/4000", 1.0 / 4000.0),
        ("1/2000", 1.0 / 2000.0),
        ("1/1000", 1.0 / 1000.0),
        ("1/500",  1.0 / 500.0),
        ("1/250",  1.0 / 250.0),
        ("1/125",  1.0 / 125.0),
        ("1/60",   1.0 / 60.0),
        ("1/30",   1.0 / 30.0),
        ("1/15",   1.0 / 15.0),
        ("1/8",    1.0 / 8.0),
        ("1/4",    1.0 / 4.0),
        ("1/2",    1.0 / 2.0),
        ("1\"",    1.0),
    ]

    /// Returns the display label for a shutter speed value.
    public static func shutterSpeedLabel(for value: Float) -> String {
        for (label, v) in commonShutterSpeeds {
            if abs(v - value) / max(abs(v), 1e-6) < 0.01 { return label }
        }
        if value >= 1.0 {
            return String(format: "%.1f\"", value)
        }
        return "1/\(Int(round(1.0 / value)))"
    }
}
