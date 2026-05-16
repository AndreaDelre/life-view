import Core
import DesignSystem
import GoogleAuth
import SwiftUI

/// Root view of the tasks corner.
///
/// Two rendering paths driven by ``TasksViewModel/state``:
///
/// - Single mode: list picker on top, new-task capture row, scrollable
///   tasks below.
/// - All-accounts mode: a single scrollable view with one section per
///   account, each section listing every list with its tasks underneath.
struct TasksView: View {
    @Bindable var viewModel: TasksViewModel
    @State private var newTaskTitle: String = ""
    @State private var newTaskDue: Date?
    @State private var selectedTaskID: String?
    @State private var editingTaskID: String?
    @FocusState private var newTaskFieldFocused: Bool

    /// Builds a `Binding<Bool>` for one row's inline-edit state, threading
    /// through the shared `editingTaskID`. Setting `true` records this
    /// row as the active editor; setting `false` only clears the editor
    /// if it was this row (a stale set-false from a different row must
    /// not steal the lock).
    private func editingBinding(for taskID: String) -> Binding<Bool> {
        Binding(
            get: { editingTaskID == taskID },
            set: { isEditing in
                if isEditing {
                    editingTaskID = taskID
                } else if editingTaskID == taskID {
                    editingTaskID = nil
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = viewModel.lastError {
                ErrorToast(message: message) {
                    viewModel.dismissError()
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            switch viewModel.state {
            case .idle, .loading:
                loadingPlaceholder
            case let .error(message):
                ErrorState(message: message) { Task { await viewModel.refresh() } }
            case let .singleLoaded(payload):
                singleContent(payload)
            case let .allLoaded(sections):
                allContent(sections)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.lastError)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            // Hidden ⌘N shortcut: focuses the new-task field when in
            // single mode. Lives on the root view so it's active
            // regardless of which sub-view has focus.
            Button("Nouvelle tâche", action: focusNewTaskField)
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    private func focusNewTaskField() {
        guard case .singleLoaded = viewModel.state else { return }
        newTaskFieldFocused = true
    }

    private func submitNewTask() {
        guard viewModel.createTask(title: newTaskTitle, due: newTaskDue) else { return }
        newTaskTitle = ""
        newTaskDue = nil
        // Keep focus so the user can keep typing additional tasks
        // without re-pressing ⌘N or clicking the field.
        newTaskFieldFocused = true
    }

    // MARK: - Single mode

    @ViewBuilder
    private func singleContent(_ payload: TasksViewModel.SinglePayload) -> some View {
        if payload.lists.isEmpty {
            EmptyState(
                icon: "tray",
                title: "Aucune liste",
                message: "Ce compte Google n'a pas encore de liste de tâches."
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                singleToolbar(payload)
                Divider()
                NewTaskRow(
                    title: $newTaskTitle,
                    due: $newTaskDue,
                    fieldFocused: $newTaskFieldFocused,
                    onSubmit: submitNewTask
                )
                Divider()
                singleTasksSection(payload)
            }
        }
    }

    private func singleToolbar(_ payload: TasksViewModel.SinglePayload) -> some View {
        let selectionBinding = Binding<String>(
            get: { payload.selectedListID ?? payload.lists.first?.id ?? "" },
            set: { viewModel.selectList($0) }
        )

        return HStack(spacing: 6) {
            Picker("Liste", selection: selectionBinding) {
                ForEach(payload.lists) { list in
                    Text(list.title).tag(list.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.regular)

            Spacer(minLength: 0)

            CompletedToggle(showsCompleted: viewModel.showsCompleted) {
                viewModel.toggleShowsCompleted()
            }
            RefreshButton(isRefreshing: viewModel.isRefreshing) {
                Task { await viewModel.refresh() }
            }
        }
    }

    @ViewBuilder
    private func singleTasksSection(_ payload: TasksViewModel.SinglePayload) -> some View {
        switch payload.tasksState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .error(message):
            ErrorState(message: message) { Task { await viewModel.refresh() } }
        case let .loaded(tasks):
            if tasks.isEmpty {
                EmptyState(
                    icon: "checkmark.seal",
                    title: viewModel.showsCompleted ? "Liste vide" : "Tout est fait !",
                    message: viewModel.showsCompleted
                        ? "Aucune tâche dans cette liste."
                        : "Aucune tâche ouverte. Active l’œil pour voir les tâches terminées."
                )
                .refreshable { await viewModel.refresh() }
            } else {
                singleTasksListIfReady(tasks: tasks, payload: payload)
            }
        }
    }

    @ViewBuilder
    private func singleTasksListIfReady(
        tasks: [TaskItem],
        payload: TasksViewModel.SinglePayload
    ) -> some View {
        if case let .single(accountID) = viewModel.selection,
           let listID = payload.selectedListID {
            singleTasksList(tasks: tasks, accountID: accountID, listID: listID)
        }
    }

    private func singleTasksList(
        tasks: [TaskItem],
        accountID: AccountID,
        listID: String
    ) -> some View {
        List(selection: $selectedTaskID) {
            ForEach(tasks) { task in
                TaskRowView(
                    task: task,
                    isPending: viewModel.isPending(taskID: task.id),
                    isEditing: editingBinding(for: task.id),
                    onToggleCompletion: { isCompleted in
                        viewModel.setCompletion(isCompleted, for: task.id, in: listID, account: accountID)
                    },
                    onEditTitle: { newTitle in
                        viewModel.editTaskTitle(newTitle, for: task.id, in: listID, account: accountID)
                    },
                    onDelete: {
                        viewModel.deleteTask(taskID: task.id, in: listID, account: accountID)
                    }
                )
                .tag(task.id)
                .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.refresh() }
        // Space → toggle completion of the selected row.
        .onKeyPress(.space) {
            guard let id = selectedTaskID,
                  let task = tasks.first(where: { $0.id == id }) else { return .ignored }
            viewModel.setCompletion(
                task.status != .completed,
                for: id,
                in: listID,
                account: accountID
            )
            return .handled
        }
        // ⌫ → delete the selected row. No confirm — tasks are cheap to
        // re-create, and the operation rolls back on a server-side
        // failure anyway.
        .onKeyPress(.delete) {
            guard let id = selectedTaskID else { return .ignored }
            viewModel.deleteTask(taskID: id, in: listID, account: accountID)
            selectedTaskID = nil
            return .handled
        }
        // Return → enter inline edit on the selected row.
        .onKeyPress(.return) {
            guard let id = selectedTaskID else { return .ignored }
            editingTaskID = id
            return .handled
        }
    }

    // MARK: - All-accounts mode

    @ViewBuilder
    private func allContent(_ sections: [TasksViewModel.AccountSection]) -> some View {
        if sections.isEmpty {
            EmptyState(
                icon: "person.2",
                title: "Aucun compte",
                message: "Ajoute un compte Google pour voir tes tâches ici."
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Tous les comptes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    CompletedToggle(showsCompleted: viewModel.showsCompleted) {
                        viewModel.toggleShowsCompleted()
                    }
                    RefreshButton(isRefreshing: viewModel.isRefreshing) {
                        Task { await viewModel.refresh() }
                    }
                }
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(sections) { section in
                            AccountSectionView(
                                section: section,
                                viewModel: viewModel,
                                editingBinding: editingBinding
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.refresh() }
            }
        }
    }

    // MARK: - Placeholders

    private var loadingPlaceholder: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Aggregated section

private struct AccountSectionView: View {
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

private struct ListSliceView: View {
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
                    // Aggregated mode renders rows inside a VStack
                    // (one ScrollView for the whole panel), so swipes
                    // and List-driven keyboard shortcuts are not
                    // available here — checkbox tap, context menu and
                    // double-click to edit cover the same mutations.
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

// MARK: - Toolbar pieces (shared)

private struct CompletedToggle: View {
    let showsCompleted: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: showsCompleted ? "eye.fill" : "eye.slash")
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.borderless)
        .help(showsCompleted ? "Masquer les tâches terminées" : "Afficher les tâches terminées")
        .accessibilityLabel(showsCompleted ? "Masquer les tâches terminées" : "Afficher les tâches terminées")
    }
}

private struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .opacity(isRefreshing ? 0 : 1)
                if isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .disabled(isRefreshing)
        .help("Rafraîchir")
        .accessibilityLabel("Rafraîchir")
    }
}

// MARK: - Reusable states

private struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
            Button("Réessayer", action: retry)
                .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
