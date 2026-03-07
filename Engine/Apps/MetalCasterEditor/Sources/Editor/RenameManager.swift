import Foundation
import SwiftUI
import MetalCasterCore

/// Identifies what is currently being renamed across the entire editor.
/// Only one item can be in rename mode at a time.
public enum RenameTarget: Equatable {
    case entity(Entity)
    case collection(UUID)
    case asset(UUID)
}

/// Centralized rename state shared by all editor views.
/// Setting `target` activates rename mode; setting it to `nil` ends it.
@Observable
public final class RenameManager {
    public var target: RenameTarget? = nil

    public func beginRename(_ target: RenameTarget) {
        self.target = target
    }

    public func endRename() {
        target = nil
    }

    public func isRenaming(_ entity: Entity) -> Bool {
        target == .entity(entity)
    }

    public func isRenamingCollection(_ id: UUID) -> Bool {
        target == .collection(id)
    }

    public func isRenamingAsset(_ guid: UUID) -> Bool {
        target == .asset(guid)
    }
}

// MARK: - RenameField

/// Grabs keyboard focus via `selectText` the moment it enters a window.
#if canImport(AppKit)
private class AutoFocusTextField: NSTextField {
    private var hasFocused = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !hasFocused else { return }
        hasFocused = true
        // Single async hop so we run after SwiftUI's layout pass completes.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            // selectText both makes the field first-responder AND selects all
            // text in one operation — avoids the resign/re-become cycle that
            // makeFirstResponder + selectText causes.
            self.selectText(nil)
        }
    }
}

/// NSTextField wrapper that auto-acquires focus on creation, selects all text,
/// and commits on Return / Escape / blur.
struct RenameField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = AutoFocusTextField()
        field.stringValue = text
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 11)
        field.textColor = .white
        field.focusRingType = .none
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.lineBreakMode = .byClipping
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.onTextChange = { self.text = $0 }
        context.coordinator.onCommit = self.onCommit

        // NEVER set stringValue while the field editor is active —
        // doing so dismisses the editor and triggers controlTextDidEndEditing.
        if nsView.currentEditor() == nil, nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var onTextChange: ((String) -> Void)?
        var onCommit: (() -> Void)?
        private var didCommit = false

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            onTextChange?(field.stringValue)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard !didCommit else { return }
            didCommit = true
            onCommit?()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                didCommit = true
                onCommit?()
                DispatchQueue.main.async { [weak self] in self?.didCommit = false }
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                didCommit = true
                onCommit?()
                DispatchQueue.main.async { [weak self] in self?.didCommit = false }
                return true
            }
            return false
        }
    }
}
#endif
