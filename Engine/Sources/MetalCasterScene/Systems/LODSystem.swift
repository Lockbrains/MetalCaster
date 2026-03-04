import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer

/// Selects the appropriate LOD mesh for each entity based on distance to the active camera.
///
/// Runs after TransformSystem and CameraSystem so that world positions and camera
/// position are up to date. Updates `MeshComponent.meshType` and `LODComponent.activeLevelIndex`.
public final class LODSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { -50 }

    nonisolated(unsafe) private var cameraSystem: CameraSystem?

    public init() {}

    public func setup(world: World) {
        // CameraSystem is resolved at first update via the engine reference
    }

    public func update(context: UpdateContext) {
        if cameraSystem == nil {
            cameraSystem = context.engine.getSystem(CameraSystem.self)
        }
        guard let cam = cameraSystem else { return }
        let camPos = cam.cameraPosition

        for entity in context.world.entities {
            guard var lod = context.world.getComponent(LODComponent.self, from: entity),
                  var mesh = context.world.getComponent(MeshComponent.self, from: entity),
                  let transform = context.world.getComponent(TransformComponent.self, from: entity),
                  !lod.levels.isEmpty else { continue }

            let entityPos = SIMD3<Float>(
                transform.worldMatrix.columns.3.x,
                transform.worldMatrix.columns.3.y,
                transform.worldMatrix.columns.3.z
            )
            let dist = simd_length(entityPos - camPos)

            var selectedIndex = lod.levels.count - 1
            for (i, level) in lod.levels.enumerated() {
                if dist <= level.maxDistance {
                    selectedIndex = i
                    break
                }
            }

            if selectedIndex != lod.activeLevelIndex {
                lod.activeLevelIndex = selectedIndex
                mesh.meshType = lod.levels[selectedIndex].meshType
                context.world.addComponent(lod, to: entity)
                context.world.addComponent(mesh, to: entity)
            }
        }
    }
}
