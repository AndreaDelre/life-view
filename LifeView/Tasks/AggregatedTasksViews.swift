import Core
import DesignSystem
import GoogleAuth
import SwiftUI

/// Aggregated-mode rendering helpers. One `AccountSectionView` per
/// signed-in account, each with one `ListSliceView` per list and per-
/// task rows that thread the same mutation callbacks as single mode.
/// Lives in its own file so `TasksView.swift` stays under the
/// SwiftLint file-length budget — the aggregated rendering is large
/// because it has to thread account context down to every row.
///
/// Aggregated mode wraps everything in a `VStack` / `ScrollView`, not
/// a SwiftUI `List`, so swipe actions and List-driven keyboard
/// shortcuts (Space / ⌫ / Return) are unavailable here. The
/// checkbox tap, context menu and double-click-to-edit gestures on
/// each `TaskRowView` cover the same mutations.
struct AccountSectionView: View {
    let section: TasksViewModel.AccountSection
    @Bindable var viewModel: TasksViewModel
    let editingBinding: (String) -> Binding<Bool>

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            ForEach(section.slices) { slice in
                ListSliceView(
                    slice: slice,
                    accountID: section.account.id,
                    viewModel: viewModel,
                    editingBinding: editingBinding
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            AccountAvatarView(url: section.account.profile.avatarURL)
                .frame(width: IconSize.md, height: IconSize.md)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                if let name = section.account.profile.displayName, !name.isEmpty {
                    Text(name).font(Typography.titleSmall)
                }
                Text(section.account.profile.email)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xxs)
        // Header per account in aggregated mode — combine the avatar +
        // display name + email into one VoiceOver stop and tag it as a
        // header so users can jump between accounts with the rotor.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct ListSliceView: View {
    let slice: TasksViewModel.ListSlice
    let accountID: AccountID
    @Bindable var viewModel: TasksViewModel
    let editingBinding: (String) -> Binding<Bool>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(slice.list.title)
                .font(Typography.subheadline)
                .foregroundStyle(Palette.textPrimary)
                .padding(.leading, Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            switch slice.tasksState {
            case .loading:
                HStack { ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.leading, Spacing.xs)
                .accessibilityLabel("Chargement des tâches de \(slice.list.title)")
            case let .error(message):
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.leading, Spacing.xs)
            case let .loaded(tasks):
                if tasks.isEmpty {
                    Text("—")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.leading, Spacing.xs)
                        .accessibilityLabel("Aucune tâche dans \(slice.list.title)")
                } else {
                    tasksStack(tasks)
                }
            }
        }
    }

    /// Per-row animated stack. Insertions slide down + fade-in from the
    /// top (the `NewTaskRow` is anchored there in single mode, and the
    /// same direction reads as natural here too). Deletions slide out
    /// to the leading edge — the trailing edge is where the swipe-to-
    /// delete affordance lives, so pushing the row in the opposite
    /// direction would fight the swipe gesture; leading also matches
    /// the RTL-aware "out of the way" reading direction. Reduce-motion
    /// collapses both into a plain opacity cross-fade.
    private func tasksStack(_ tasks: [TaskItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(tasks) { task in
                TaskRowView(
                    task: task,
                    isPending: viewModel.isPending(taskID: task.id),
                    isEditing: editingBinding(task.id),
                    onToggleCompletion: { isCompleted in
                        viewModel.setCompletion(
                            isCompleted,
                            for: task.id,
                            in: slice.list.id,
                            account: accountID
                        )
                    },
                    onEditTitle: { newTitle in
                        viewModel.editTaskTitle(
                            newTitle,
                            for: task.id,
                            in: slice.list.id,
                            account: accountID
                        )
                    },
                    onDelete: {
                        viewModel.deleteTask(
                            taskID: task.id,
                            in: slice.list.id,
                            account: accountID
                        )
                    }
                )
                // 1pt hairline separation — too small for a
                // named spacing token, intentionally sub-grid.
                .padding(.vertical, 1)
                .transition(reduceMotion ? Motion.rowReducedTransition : Motion.rowTransition)
            }
        }
        .animation(reduceMotion ? Motion.reduced : Motion.standard, value: tasks.map(\.id))
    }
}
