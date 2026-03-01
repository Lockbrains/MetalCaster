import Foundation

/// Abstract input action that maps to device-specific inputs.
public struct InputAction: Hashable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

/// The current state of an input action.
public enum InputState: Sendable {
    case pressed
    case held
    case released
    case inactive
}

/// Cross-platform input abstraction layer.
///
/// Maps device-specific inputs (keyboard, mouse, touch, gamepad)
/// to abstract InputActions that game systems can query.
public final class InputManager: @unchecked Sendable {
    
    /// Registered action bindings.
    private var bindings: [InputAction: [String]] = [:]
    
    /// Current state of all tracked inputs (keyed by raw input identifier).
    private var rawStates: [String: InputState] = [:]
    
    /// Mouse/touch position in normalized coordinates [0, 1].
    public var pointerPosition: (x: Float, y: Float) = (0.5, 0.5)
    
    /// Mouse/touch delta since last frame.
    public var pointerDelta: (dx: Float, dy: Float) = (0, 0)
    
    /// Scroll wheel delta.
    public var scrollDelta: Float = 0
    
    public init() {}
    
    // MARK: - Action Binding
    
    /// Binds an abstract action to one or more raw input identifiers.
    public func bind(_ action: InputAction, to rawInputs: [String]) {
        bindings[action] = rawInputs
    }
    
    /// Returns the current state of an action.
    public func state(of action: InputAction) -> InputState {
        guard let rawInputs = bindings[action] else { return .inactive }
        for raw in rawInputs {
            if let state = rawStates[raw], state != .inactive {
                return state
            }
        }
        return .inactive
    }
    
    /// Returns true if the action is currently pressed or held.
    public func isActive(_ action: InputAction) -> Bool {
        let s = state(of: action)
        return s == .pressed || s == .held
    }
    
    /// Returns true if the action was just pressed this frame.
    public func isPressed(_ action: InputAction) -> Bool {
        state(of: action) == .pressed
    }
    
    // MARK: - Raw Input Updates (called by platform layer)
    
    /// Reports a raw input event from the platform layer.
    public func reportInput(_ identifier: String, state: InputState) {
        rawStates[identifier] = state
    }
    
    /// Called at the end of each frame to transition pressed -> held and released -> inactive.
    public func endFrame() {
        for (key, state) in rawStates {
            switch state {
            case .pressed: rawStates[key] = .held
            case .released: rawStates[key] = .inactive
            default: break
            }
        }
        pointerDelta = (0, 0)
        scrollDelta = 0
    }
    
    /// Resets all input states.
    public func reset() {
        rawStates.removeAll()
        pointerPosition = (0.5, 0.5)
        pointerDelta = (0, 0)
        scrollDelta = 0
    }
}
