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
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onAppear {
                        draft = text
                        fieldFocused = true
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
            } else {
                Text(text)
            }
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
}
