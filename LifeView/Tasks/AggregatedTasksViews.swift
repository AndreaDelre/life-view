import Core
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
        VStack(alignment: .leading, spacing: 6) {
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
        HStack(spacing: 8) {
            AccountAvatarView(url: section.account.profile.avatarURL)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                if let name = section.account.profile.displayName, !name.isEmpty {
                    Text(name).font(.callout.weight(.semibold))
                }
                Text(section.account.profile.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

struct ListSliceView: View {
    let slice: TasksViewModel.ListSlice
    let accountID: AccountID
    @Bindable var viewModel: TasksViewModel
    let editingBinding: (String) -> Binding<Bool>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(slice.list.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.leading, 4)
            switch slice.tasksState {
            case .loading:
                HStack { ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.leading, 4)
            case let .error(message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            case let .loaded(tasks):
                if tasks.isEmpty {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                } else {
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
                            .padding(.vertical, 1)
                        }
                    }
                }
            }
        }
    }
}
