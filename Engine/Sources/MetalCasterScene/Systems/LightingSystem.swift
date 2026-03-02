import Foundation
import simd
import MetalCasterCore

/// GPU-friendly light data structure, packed for upload to a Metal buffer.
public struct GPULightData: Sendable {
    public var position: SIMD3<Float> = .zero
    public var _pad0: Float = 0
    public var direction: SIMD3<Float> = SIMD3<Float>(0, -1, 0)
    public var _pad1: Float = 0
    public var color: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    public var intensity: Float = 1.0
    public var range: Float = 10.0
    public var innerConeAngle: Float = 0.5
    public var outerConeAngle: Float = 0.7
    public var type: UInt32 = 0 // 0=directional, 1=point, 2=spot
}

/// Collects all light entities and prepares GPU-ready light data.
///
/// Outputs are consumed by the renderer to bind light data at buffer index 3
/// and light count at buffer index 4 for lit materials.
public final class LightingSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { -80 }
    
    /// GPU-ready light data array, updated each frame.
    public nonisolated(unsafe) var lights: [GPULightData] = []
    
    /// Maximum number of lights supported.
    public nonisolated(unsafe) var maxLights: Int = 16

    /// A default directional light used when no light entities exist in the scene.
    public static let defaultDirectionalLight: GPULightData = {
        var light = GPULightData()
        light.direction = SIMD3<Float>(0.4, -0.9, -0.5)
        light.color = SIMD3<Float>(1, 1, 1)
        light.intensity = 1.0
        light.type = 0
        return light
    }()
    
    public init() {}
    
    public func update(context: UpdateContext) {
        let lightEntities = context.world.query(TransformComponent.self, LightComponent.self)
        
        var gpuLights: [GPULightData] = []
        
        for (_, tc, lc) in lightEntities.prefix(maxLights) {
            var gpu = GPULightData()
            
            let wm = tc.worldMatrix
            gpu.position = SIMD3<Float>(wm.columns.3.x, wm.columns.3.y, wm.columns.3.z)
            
            // Forward direction is -Z in the entity's local space
            gpu.direction = -normalize(SIMD3<Float>(wm.columns.2.x, wm.columns.2.y, wm.columns.2.z))
            
            gpu.color = lc.color
            gpu.intensity = lc.intensity
            gpu.range = lc.range
            gpu.innerConeAngle = lc.innerConeAngle
            gpu.outerConeAngle = lc.outerConeAngle
            
            switch lc.type {
            case .directional: gpu.type = 0
            case .point: gpu.type = 1
            case .spot: gpu.type = 2
            }
            
            gpuLights.append(gpu)
        }

        if gpuLights.isEmpty {
            gpuLights.append(Self.defaultDirectionalLight)
        }
        
        lights = gpuLights
    }

    /// The number of active lights (clamped to maxLights).
    public var lightCount: UInt32 {
        UInt32(min(lights.count, maxLights))
    }

    /// Total byte size of the light data buffer for GPU upload.
    public var lightBufferSize: Int {
        lights.count * MemoryLayout<GPULightData>.stride
    }
}
