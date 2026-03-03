import Foundation
import simd
import MetalCasterCore
import MetalCasterScene
import MetalCasterRenderer

// MARK: - Entity Snapshot

/// Captures the complete state of an entity for undo/redo and copy/paste.
/// Uses explicit component types (mirrors SceneSerializer's EntityData).
public struct EntitySnapshot {
    public var name: NameComponent?
    public var transform: TransformComponent?
    public var mesh: MeshComponent?
    public var material: MaterialComponent?
    public var camera: CameraComponent?
    public var light: LightComponent?
    public var manager: ManagerComponent?
    public var skybox: SkyboxComponent?
    public var postProcessVolume: PostProcessVolumeComponent?
    public var gameplayScriptRef: GameplayScriptRef?

    public static func capture(entity: Entity, world: World) -> EntitySnapshot {
        EntitySnapshot(
            name: world.getComponent(NameComponent.self, from: entity),
            transform: world.getComponent(TransformComponent.self, from: entity),
            mesh: world.getComponent(MeshComponent.self, from: entity),
            material: world.getComponent(MaterialComponent.self, from: entity),
            camera: world.getComponent(CameraComponent.self, from: entity),
            light: world.getComponent(LightComponent.self, from: entity),
            manager: world.getComponent(ManagerComponent.self, from: entity),
            skybox: world.getComponent(SkyboxComponent.self, from: entity),
            postProcessVolume: world.getComponent(PostProcessVolumeComponent.self, from: entity),
            gameplayScriptRef: world.getComponent(GameplayScriptRef.self, from: entity)
        )
    }

    public func restore(to entity: Entity, world: World) {
        if let name { world.addComponent(name, to: entity) }
        if let transform { world.addComponent(transform, to: entity) }
        if let mesh { world.addComponent(mesh, to: entity) }
        if let material { world.addComponent(material, to: entity) }
        if let camera { world.addComponent(camera, to: entity) }
        if let light { world.addComponent(light, to: entity) }
        if let manager { world.addComponent(manager, to: entity) }
        if let skybox { world.addComponent(skybox, to: entity) }
        if let postProcessVolume { world.addComponent(postProcessVolume, to: entity) }
        if let gameplayScriptRef { world.addComponent(gameplayScriptRef, to: entity) }
    }

    public var displayName: String {
        name?.name ?? "Entity"
    }
}

// MARK: - Create Entity Command

public final class CreateEntityCommand: EditorCommand {
    private let snapshot: EntitySnapshot
    var trackedEntityID: UInt64?

    public var description: String { "Create '\(snapshot.displayName)'" }

    public init(snapshot: EntitySnapshot, initialEntityID: UInt64? = nil) {
        self.snapshot = snapshot
        self.trackedEntityID = initialEntityID
    }

    public func execute(state: EditorState) {
        let entity = state.engine.world.createEntity()
        snapshot.restore(to: entity, world: state.engine.world)
        trackedEntityID = entity.id
        state.selectedEntity = entity
    }

    public func undo(state: EditorState) {
        guard let id = trackedEntityID else { return }
        for entity in state.engine.world.entities where entity.id == id {
            state.engine.world.destroyEntity(entity)
            if state.selectedEntity == entity { state.selectedEntity = nil }
            break
        }
    }
}

// MARK: - Delete Entity Command

public final class DeleteEntityCommand: EditorCommand {
    private let snapshot: EntitySnapshot
    private var trackedEntityID: UInt64?

    public var description: String { "Delete '\(snapshot.displayName)'" }

    public init(entityID: UInt64, snapshot: EntitySnapshot) {
        self.trackedEntityID = entityID
        self.snapshot = snapshot
    }

    public func execute(state: EditorState) {
        guard let id = trackedEntityID else { return }
        for entity in state.engine.world.entities where entity.id == id {
            state.engine.world.destroyEntity(entity)
            if state.selectedEntity == entity { state.selectedEntity = nil }
            break
        }
    }

    public func undo(state: EditorState) {
        let entity = state.engine.world.createEntity()
        snapshot.restore(to: entity, world: state.engine.world)
        trackedEntityID = entity.id
        state.selectedEntity = entity
    }
}

// MARK: - Transform Change Command

public final class TransformChangeCommand: EditorCommand {
    private let entityID: UInt64
    private let oldTransform: MCTransform
    private let newTransform: MCTransform

    public var description: String { "Transform Change" }

    public init(entityID: UInt64, oldTransform: MCTransform, newTransform: MCTransform) {
        self.entityID = entityID
        self.oldTransform = oldTransform
        self.newTransform = newTransform
    }

    public func execute(state: EditorState) {
        applyTransform(newTransform, state: state)
    }

    public func undo(state: EditorState) {
        applyTransform(oldTransform, state: state)
    }

    private func applyTransform(_ t: MCTransform, state: EditorState) {
        for entity in state.engine.world.entities where entity.id == entityID {
            guard var tc = state.engine.world.getComponent(TransformComponent.self, from: entity) else { return }
            tc.transform = t
            state.engine.world.addComponent(tc, to: entity)
            break
        }
    }
}

// MARK: - Component Change Command

/// Records before/after entity state for component edits.
/// Coalesced by EditorState so that continuous slider drags produce a single undo entry.
public final class ComponentChangeCommand: EditorCommand {
    private let entityID: UInt64
    private let beforeSnapshot: EntitySnapshot
    private let afterSnapshot: EntitySnapshot

    public var description: String { "Edit '\(beforeSnapshot.displayName)'" }

    public init(entityID: UInt64, beforeSnapshot: EntitySnapshot, afterSnapshot: EntitySnapshot) {
        self.entityID = entityID
        self.beforeSnapshot = beforeSnapshot
        self.afterSnapshot = afterSnapshot
    }

    public func execute(state: EditorState) {
        applySnapshot(afterSnapshot, state: state)
    }

    public func undo(state: EditorState) {
        applySnapshot(beforeSnapshot, state: state)
    }

    private func applySnapshot(_ snapshot: EntitySnapshot, state: EditorState) {
        for entity in state.engine.world.entities where entity.id == entityID {
            snapshot.restore(to: entity, world: state.engine.world)
            state.selectedEntity = entity
            break
        }
    }
}

// MARK: - Undo/Redo Extensions

extension EditorState {

    /// Execute a command (for redo or fresh execution) and push to undo stack.
    public func executeCommand(_ command: EditorCommand) {
        command.execute(state: self)
        undoStack.append(command)
        redoStack.removeAll()
        worldRevision += 1
        markDirty()
    }

    /// Record a command that was already performed, pushing it to the undo stack without re-executing.
    public func recordCommand(_ command: EditorCommand) {
        undoStack.append(command)
        redoStack.removeAll()
    }

    public func undoLast() {
        commitPendingEdit()
        guard let command = undoStack.popLast() else { return }
        command.undo(state: self)
        redoStack.append(command)
        worldRevision += 1
        markDirty()
    }

    public func redoLast() {
        commitPendingEdit()
        guard let command = redoStack.popLast() else { return }
        command.execute(state: self)
        undoStack.append(command)
        worldRevision += 1
        markDirty()
    }
}
