import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer

/// Evaluates all PostProcessVolumeComponent entities each frame and produces
/// a merged set of post-processing settings based on camera position and volume priority.
public final class PostProcessVolumeSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { -80 }

    /// The resolved settings after evaluating all active volumes.
    public nonisolated(unsafe) var resolvedSettings = PostProcessVolumeComponent()

    /// Whether any post-process volume exists in the scene.
    public nonisolated(unsafe) var hasActiveVolume: Bool = false

    public init() {}

    public func update(context: UpdateContext) {
        let volumes = context.world.query(PostProcessVolumeComponent.self)
        guard !volumes.isEmpty else {
            hasActiveVolume = false
            return
        }

        let transforms = context.world.query(TransformComponent.self, PostProcessVolumeComponent.self)

        let cameraPos = findCameraPosition(world: context.world)

        var activeVolumes: [(component: PostProcessVolumeComponent, weight: Float)] = []

        for (_, transform, volume) in transforms {
            if volume.isGlobal {
                activeVolumes.append((volume, 1.0))
                continue
            }

            let worldMatrix = transform.worldMatrix
            let volumeCenter = SIMD3<Float>(worldMatrix.columns.3.x, worldMatrix.columns.3.y, worldMatrix.columns.3.z)
            let localPos = cameraPos - volumeCenter
            let extents = volume.volumeExtents

            let insideX = abs(localPos.x) <= extents.x
            let insideY = abs(localPos.y) <= extents.y
            let insideZ = abs(localPos.z) <= extents.z

            if insideX && insideY && insideZ {
                let weight: Float
                if volume.blendDistance > 0 {
                    let dx = max(0, abs(localPos.x) - extents.x + volume.blendDistance) / volume.blendDistance
                    let dy = max(0, abs(localPos.y) - extents.y + volume.blendDistance) / volume.blendDistance
                    let dz = max(0, abs(localPos.z) - extents.z + volume.blendDistance) / volume.blendDistance
                    weight = 1.0 - max(dx, max(dy, dz))
                } else {
                    weight = 1.0
                }
                if weight > 0 {
                    activeVolumes.append((volume, weight))
                }
            }
        }

        guard !activeVolumes.isEmpty else {
            hasActiveVolume = false
            return
        }

        hasActiveVolume = true

        activeVolumes.sort { $0.component.priority < $1.component.priority }

        var merged = PostProcessVolumeComponent()
        for (volume, _) in activeVolumes {
            mergeVolume(into: &merged, from: volume)
        }

        resolvedSettings = merged
    }

    private func findCameraPosition(world: World) -> SIMD3<Float> {
        let cameras = world.query(TransformComponent.self, CameraComponent.self)
        guard let (_, tc, _) = cameras.first(where: { $0.2.isActive }) ?? cameras.first else {
            return .zero
        }
        let m = tc.worldMatrix
        return SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
    }

    /// Higher-priority volume settings override lower ones (last-write-wins for enabled effects).
    private func mergeVolume(into target: inout PostProcessVolumeComponent, from source: PostProcessVolumeComponent) {
        if source.bloom.enabled { target.bloom = source.bloom }
        if source.chromaticAberration.enabled { target.chromaticAberration = source.chromaticAberration }
        if source.colorAdjustments.enabled { target.colorAdjustments = source.colorAdjustments }
        if source.channelMixer.enabled { target.channelMixer = source.channelMixer }
        if source.depthOfField.enabled { target.depthOfField = source.depthOfField }
        if source.filmGrain.enabled { target.filmGrain = source.filmGrain }
        if source.lensDistortion.enabled { target.lensDistortion = source.lensDistortion }
        if source.liftGammaGain.enabled { target.liftGammaGain = source.liftGammaGain }
        if source.motionBlur.enabled { target.motionBlur = source.motionBlur }
        if source.paniniProjection.enabled { target.paniniProjection = source.paniniProjection }
        if source.shadowsMidtonesHighlights.enabled { target.shadowsMidtonesHighlights = source.shadowsMidtonesHighlights }
        if source.splitToning.enabled { target.splitToning = source.splitToning }
        if source.tonemapping.enabled { target.tonemapping = source.tonemapping }
        if source.vignette.enabled { target.vignette = source.vignette }
        if source.whiteBalance.enabled { target.whiteBalance = source.whiteBalance }
        if source.ambientOcclusion.enabled { target.ambientOcclusion = source.ambientOcclusion }
        if source.antiAliasing.enabled { target.antiAliasing = source.antiAliasing }
        if source.fullscreenBlur.enabled { target.fullscreenBlur = source.fullscreenBlur }
        if source.fullscreenOutline.enabled { target.fullscreenOutline = source.fullscreenOutline }
    }
}
