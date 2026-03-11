import Foundation
import simd
import MetalCasterCore

// MARK: - GPU Data Structures

/// GPU-ready light probe data for uploading to Metal buffers.
public struct GPULightProbeData: Sendable {
    public var position: SIMD3<Float> = .zero
    public var radius: Float = 10.0
    /// SH L2 coefficients packed as 3×9 = 27 floats (R0..R8, G0..G8, B0..B8).
    public var shR: (Float, Float, Float, Float, Float, Float, Float, Float, Float) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0)
    public var shG: (Float, Float, Float, Float, Float, Float, Float, Float, Float) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0)
    public var shB: (Float, Float, Float, Float, Float, Float, Float, Float, Float) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0)
    public var intensity: Float = 1.0
    public var _pad0: Float = 0
    public var _pad1: Float = 0
    public var _pad2: Float = 0
}

/// GPU-ready reflection probe data.
public struct GPUReflectionProbeData: Sendable {
    public var position: SIMD3<Float> = .zero
    public var radius: Float = 10.0
    public var boxMin: SIMD3<Float> = SIMD3<Float>(-5, -5, -5)
    public var blendDistance: Float = 1.0
    public var boxMax: SIMD3<Float> = SIMD3<Float>(5, 5, 5)
    public var intensity: Float = 1.0
    /// 0 = sphere, 1 = box
    public var shape: UInt32 = 1
    public var priority: UInt32 = 0
    public var cubemapIndex: UInt32 = 0
    public var _pad0: UInt32 = 0
}

/// GPU-ready height fog parameters (single instance per scene).
public struct GPUHeightFogData: Sendable {
    public var color: SIMD3<Float> = SIMD3<Float>(0.6, 0.65, 0.75)
    public var density: Float = 0.02
    public var baseHeight: Float = 0.0
    public var heightFalloff: Float = 0.2
    public var maxOpacity: Float = 1.0
    public var startDistance: Float = 0.0
    public var inscatteringColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.9, 0.7)
    public var inscatteringIntensity: Float = 0.0
    public var inscatteringExponent: Float = 8.0
    /// 0 = exponential, 1 = exponential squared
    public var mode: UInt32 = 0
    public var enabled: UInt32 = 0
    public var _pad0: UInt32 = 0
}

// MARK: - Probe System

/// Collects light probes, reflection probes, and height fog entities
/// into GPU-ready arrays consumed by the renderer.
public final class ProbeSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { -75 }

    public nonisolated(unsafe) var lightProbes: [GPULightProbeData] = []
    public nonisolated(unsafe) var reflectionProbes: [GPUReflectionProbeData] = []
    public nonisolated(unsafe) var heightFog: GPUHeightFogData = GPUHeightFogData()

    public static let maxLightProbes: Int = 32
    public static let maxReflectionProbes: Int = 16

    public init() {}

    public func update(context: UpdateContext) {
        updateLightProbes(context: context)
        updateReflectionProbes(context: context)
        updateHeightFog(context: context)
    }

    // MARK: - Light Probes

    private func updateLightProbes(context: UpdateContext) {
        let entities = context.world.query(TransformComponent.self, LightProbeComponent.self)
        var probes: [GPULightProbeData] = []

        for (_, tc, lpc) in entities.prefix(Self.maxLightProbes) {
            var gpu = GPULightProbeData()
            let wm = tc.worldMatrix
            gpu.position = SIMD3<Float>(wm.columns.3.x, wm.columns.3.y, wm.columns.3.z)
            gpu.radius = lpc.radius
            gpu.intensity = lpc.intensity

            let r = lpc.shCoefficientsR
            let g = lpc.shCoefficientsG
            let b = lpc.shCoefficientsB
            if r.count >= 9 {
                gpu.shR = (r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8])
            }
            if g.count >= 9 {
                gpu.shG = (g[0], g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8])
            }
            if b.count >= 9 {
                gpu.shB = (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8])
            }

            probes.append(gpu)
        }

        lightProbes = probes
    }

    // MARK: - Reflection Probes

    private func updateReflectionProbes(context: UpdateContext) {
        let entities = context.world.query(TransformComponent.self, ReflectionProbeComponent.self)
        var probes: [GPUReflectionProbeData] = []

        for (_, tc, rpc) in entities.prefix(Self.maxReflectionProbes) {
            var gpu = GPUReflectionProbeData()
            let wm = tc.worldMatrix
            let pos = SIMD3<Float>(wm.columns.3.x, wm.columns.3.y, wm.columns.3.z)
            gpu.position = pos
            gpu.radius = rpc.radius
            gpu.intensity = rpc.intensity
            gpu.blendDistance = rpc.blendDistance
            gpu.priority = UInt32(max(0, rpc.priority))

            switch rpc.shape {
            case .sphere:
                gpu.shape = 0
                gpu.boxMin = pos - SIMD3<Float>(repeating: rpc.radius)
                gpu.boxMax = pos + SIMD3<Float>(repeating: rpc.radius)
            case .box:
                gpu.shape = 1
                gpu.boxMin = pos - rpc.boxExtents
                gpu.boxMax = pos + rpc.boxExtents
            }

            probes.append(gpu)
        }

        probes.sort { $0.priority > $1.priority }
        reflectionProbes = probes
    }

    // MARK: - Height Fog

    private func updateHeightFog(context: UpdateContext) {
        let entities = context.world.query(TransformComponent.self, HeightFogComponent.self)

        guard let (_, _, fog) = entities.first else {
            var data = GPUHeightFogData()
            data.enabled = 0
            heightFog = data
            return
        }

        var data = GPUHeightFogData()
        data.color = fog.color
        data.density = fog.density
        data.baseHeight = fog.baseHeight
        data.heightFalloff = fog.heightFalloff
        data.maxOpacity = fog.maxOpacity
        data.startDistance = fog.startDistance
        data.inscatteringColor = fog.inscatteringColor
        data.inscatteringIntensity = fog.inscatteringIntensity
        data.inscatteringExponent = fog.inscatteringExponent
        data.mode = fog.mode == .exponentialSquared ? 1 : 0
        data.enabled = 1
        heightFog = data
    }

    // MARK: - Buffer Helpers

    public var lightProbeCount: UInt32 {
        UInt32(min(lightProbes.count, Self.maxLightProbes))
    }

    public var reflectionProbeCount: UInt32 {
        UInt32(min(reflectionProbes.count, Self.maxReflectionProbes))
    }

    public var lightProbeBufferSize: Int {
        max(lightProbes.count, 1) * MemoryLayout<GPULightProbeData>.stride
    }

    public var reflectionProbeBufferSize: Int {
        max(reflectionProbes.count, 1) * MemoryLayout<GPUReflectionProbeData>.stride
    }

    public var heightFogBufferSize: Int {
        MemoryLayout<GPUHeightFogData>.stride
    }
}
