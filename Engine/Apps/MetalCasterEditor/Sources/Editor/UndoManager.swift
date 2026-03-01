import Foundation
import simd
import MetalCasterCore
import MetalCasterScene

/// Command pattern implementation for undo/redo operations in the editor.

// MARK: - Transform Change Command

public struct TransformChangeCommand: EditorCommand {
    let entity: Entity
    let oldTransform: MCTransform
    let newTransform: MCTransform

    public var description: String { "Transform Change" }

    public func execute(state: EditorState) {
        guard var tc = state.engine.world.getComponent(TransformComponent.self, from: entity) else { return }
        tc.transform = newTransform
        state.engine.world.addComponent(tc, to: entity)
    }

    public func undo(state: EditorState) {
        guard var tc = state.engine.world.getComponent(TransformComponent.self, from: entity) else { return }
        tc.transform = oldTransform
        state.engine.world.addComponent(tc, to: entity)
    }
}

// MARK: - Entity Creation Command

public struct CreateEntityCommand: EditorCommand {
    let entityID: UInt64
    let name: String

    public var description: String { "Create Entity '\(name)'" }

    public func execute(state: EditorState) {
        // Entity already created; this is for redo
        state.sceneGraph.createEntity(name: name)
    }

    public func undo(state: EditorState) {
        for entity in state.engine.world.entities where entity.id == entityID {
            state.sceneGraph.destroyEntityRecursive(entity)
            if state.selectedEntity == entity {
                state.selectedEntity = nil
            }
            break
        }
    }
}

// MARK: - Entity Deletion Command

public struct DeleteEntityCommand: EditorCommand {
    let entityID: UInt64
    let name: String

    public var description: String { "Delete Entity '\(name)'" }

    public func execute(state: EditorState) {
        for entity in state.engine.world.entities where entity.id == entityID {
            state.sceneGraph.destroyEntityRecursive(entity)
            break
        }
    }

    public func undo(state: EditorState) {
        // Simplified: recreate entity with name only
        state.sceneGraph.createEntity(name: name)
    }
}

// MARK: - Undo/Redo Extensions

extension EditorState {
    public func executeCommand(_ command: EditorCommand) {
        command.execute(state: self)
        undoStack.append(command)
        redoStack.removeAll()
    }

    public func undoLast() {
        guard let command = undoStack.popLast() else { return }
        command.undo(state: self)
        redoStack.append(command)
    }

    public func redoLast() {
        guard let command = redoStack.popLast() else { return }
        command.execute(state: self)
        undoStack.append(command)
    }
}
