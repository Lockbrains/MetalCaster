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
public final class LightingSystem: System {
    public var isEnabled: Bool = true
    public var priority: Int { -80 }
    
    /// GPU-ready light data array, updated each frame.
    public private(set) var lights: [GPULightData] = []
    
    /// Maximum number of lights supported.
    public var maxLights: Int = 16
    
    public init() {}
    
    public func update(world: World, deltaTime: Float) {
        let lightEntities = world.query(TransformComponent.self, LightComponent.self)
        
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
        
        lights = gpuLights
    }
}
