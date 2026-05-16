import AppKit
import SwiftUI

/// Toggle-able inline text editor. Renders as static text by default;
/// when `isEditing` becomes `true`, swaps to a focused `TextField` and
/// pre-fills with the current value. Commits on Return or focus loss,
/// reverts on Escape (`onExitCommand`).
///
/// Used by P5 for the task title inline edit (double-click / `Return`
/// from a selected row) and the task-list rename flow. The double-tap
/// gesture lives outside this component so the caller can wire other
/// gestures (single-click selects, double-click edits) without a
/// dispatch conflict — the caller flips `isEditing` to true to enter
/// edit mode and the view drives the rest.
public struct InlineEditableText: View {
    private let text: String
    @Binding private var isEditing: Bool
    private let onCommit: (String) -> Void
    private let onCancel: () -> Void
    private let placeholder: String

    @State private var draft: String = ""
    @State private var isPrepared: Bool = false
    @FocusState private var fieldFocused: Bool

    public init(
        text: String,
        isEditing: Binding<Bool>,
        placeholder: String = "",
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.text = text
        _isEditing = isEditing
        self.placeholder = placeholder
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    public var body: some View {
        Group {
            if isEditing {
                // ZStack mask: the NSTextField backing SwiftUI's
                // TextField paints an opaque background and selects
                // its content the moment it becomes first responder.
                // We can only undo that on the next runloop tick (the
                // field editor doesn't exist before then), so during
                // that single frame we hide the TextField under a
                // matching static Text. Once `prepareFieldEditor()`
                // has cleared the background + collapsed the
                // selection, we flip the opacities and the user sees
                // a seamless transition into edit mode.
                ZStack(alignment: .leading) {
                    Text(text)
                        .opacity(isPrepared ? 0 : 1)
                        .accessibilityHidden(true)
                    TextField(placeholder, text: $draft)
                        .textFieldStyle(.plain)
                        .focused($fieldFocused)
                        .focusEffectDisabled()
                        .background(Color.clear)
                        .opacity(isPrepared ? 1 : 0)
                        .onAppear {
                            draft = text
                            fieldFocused = true
                            prepareFieldEditor()
                        }
                        .onSubmit {
                            commit()
                        }
                        .onExitCommand {
                            cancel()
                        }
                        .onChange(of: fieldFocused) { _, isFocused in
                            // Blur after the field had focus: treat as commit.
                            // Skip the initial transition (false → true on
                            // appear) by gating on the current edit mode.
                            if !isFocused, isEditing {
                                commit()
                            }
                        }
                }
            } else {
                Text(text)
            }
        }
        .onChange(of: isEditing) { _, editing in
            // Reset the mask flag when we leave edit mode so the next
            // entry starts hidden again.
            if !editing { isPrepared = false }
        }
    }

    private func commit() {
        let value = draft
        isEditing = false
        onCommit(value)
    }

    private func cancel() {
        isEditing = false
        onCancel()
    }

    /// Reaches into the window's field editor on the next runloop tick
    /// to (1) collapse the default select-all selection into a caret
    /// at the end of the string and (2) strip the opaque background
    /// SwiftUI's `.plain` TextField still draws on focus on macOS —
    /// both on the field editor itself and on the host NSTextField
    /// walked up the view hierarchy. Async because the field editor
    /// is only attached after SwiftUI processes the focus change.
    private func prepareFieldEditor() {
        DispatchQueue.main.async {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }

            editor.drawsBackground = false
            editor.backgroundColor = .clear

            var node: NSView? = editor.superview
            while let current = node {
                if let host = current as? NSTextField {
                    host.drawsBackground = false
                    host.backgroundColor = .clear
                    host.isBezeled = false
                    host.focusRingType = .none
                    break
                }
                node = current.superview
            }

            let end = (editor.string as NSString).length
            editor.selectedRange = NSRange(location: end, length: 0)

            // Flip the ZStack mask: now the TextField is safe to show.
            isPrepared = true
        }
    }
}
