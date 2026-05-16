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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .padding(.horizontal, Spacing.xs)
                .padding(.top, Spacing.xs)
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
            VStack(alignment: .leading, spacing: Spacing.sm) {
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
        HStack(spacing: Spacing.sm) {
            listMenu(payload)

            Spacer(minLength: 0)

            CompletedToggle(showsCompleted: viewModel.showsCompleted) {
                viewModel.toggleShowsCompleted()
            }
            RefreshButton(isRefreshing: viewModel.isRefreshing) {
                Task { await viewModel.refresh() }
            }
        }
    }

    /// Combined list-picker + list-CRUD entry point. Lives behind a
    /// single `Menu` to keep the toolbar compact: pick a list from the
    /// top section, then below the divider find Nouvelle / Renommer /
    /// Supprimer for the currently-selected list.
    private func listMenu(_ payload: TasksViewModel.SinglePayload) -> some View {
        let selectedTitle = payload.lists
            .first(where: { $0.id == payload.selectedListID })?.title
            ?? payload.lists.first?.title
            ?? "Listes"
        let selectedList = payload.lists.first(where: { $0.id == payload.selectedListID })

        return Menu {
            ForEach(payload.lists) { list in
                Button {
                    viewModel.selectList(list.id)
                } label: {
                    if list.id == payload.selectedListID {
                        Label(list.title, systemImage: "checkmark")
                    } else {
                        Text(list.title)
                    }
                }
            }
            Divider()
            Button {
                presentCreateList()
            } label: {
                Label("Nouvelle liste…", systemImage: "plus")
            }
            if let selectedList, !selectedList.id.hasPrefix("local-list-") {
                Divider()
                Button {
                    presentRenameList(selectedList)
                } label: {
                    Label("Renommer la liste…", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    presentDeleteList(selectedList)
                } label: {
                    Label("Supprimer la liste…", systemImage: "trash")
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(selectedTitle).lineLimit(1)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func presentCreateList() {
        guard case let .single(accountID) = viewModel.selection else { return }
        guard let title = ConfirmationAlert.prompt(
            title: "Nouvelle liste",
            message: "Donne un nom à ta nouvelle liste de tâches.",
            placeholder: "Ex. Courses",
            confirmLabel: "Créer"
        ) else { return }
        _ = viewModel.createList(title: title)
        _ = accountID
    }

    private func presentRenameList(_ list: TaskList) {
        guard case let .single(accountID) = viewModel.selection else { return }
        guard let newTitle = ConfirmationAlert.prompt(
            title: "Renommer la liste",
            placeholder: "Nom de la liste",
            initialValue: list.title,
            confirmLabel: "Renommer"
        ) else { return }
        viewModel.renameList(listID: list.id, to: newTitle, account: accountID)
    }

    private func presentDeleteList(_ list: TaskList) {
        guard case let .single(accountID) = viewModel.selection else { return }
        let confirmed = ConfirmationAlert.confirm(
            title: "Supprimer « \(list.title) » ?",
            message: "Toutes les tâches de cette liste seront aussi supprimées. Cette action est irréversible.",
            confirmLabel: "Supprimer",
            isDestructive: true
        )
        guard confirmed else { return }
        viewModel.deleteList(listID: list.id, account: accountID)
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
        if let context = singleListContext(payload: payload) {
            singleTasksList(tasks: tasks, accountID: context.accountID, listID: context.listID)
        }
    }

    private func singleListContext(payload: TasksViewModel.SinglePayload) -> (accountID: AccountID, listID: String)? {
        guard case let .single(accountID) = viewModel.selection,
              let listID = payload.selectedListID else { return nil }
        return (accountID, listID)
    }

    private func singleTasksList(
        tasks: [TaskItem],
        accountID: AccountID,
        listID: String
    ) -> some View {
        // Single-mode uses `List` (for native selection + swipe + keyboard
        // handling), which doesn't honour per-row `.transition(...)`
        // modifiers — it has its own insert/remove choreography. We
        // therefore drive the animation at the container level via
        // `.animation(_, value: tasks.map(\.id))`, which is what
        // `List` actually observes to schedule its built-in
        // fade/slide. The aggregated mode below, which uses
        // `LazyVStack`, can apply the richer custom `.transition`.
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
            // Drag-to-reorder. `.onMove` is only honored on `ForEach`
            // *inside* a `List` on macOS — it wires up the native drag
            // handle and the slide-while-dragging visual. Aggregated
            // mode (LazyVStack) is intentionally out of scope for P6.3:
            // it would require a hand-rolled NSItemProvider/.onDrop
            // pipeline.
            .onMove { indices, newOffset in
                guard let sourceIndex = indices.first else { return }
                viewModel.moveTask(
                    from: sourceIndex,
                    to: newOffset,
                    in: listID,
                    account: accountID
                )
            }
        }
        .animation(reduceMotion ? Motion.reduced : Motion.standard, value: tasks.map(\.id))
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
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Text("Tous les comptes")
                        .font(Typography.titleMedium)
                        .foregroundStyle(Palette.textSecondary)
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
                    LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                        ForEach(sections) { section in
                            AccountSectionView(
                                section: section,
                                viewModel: viewModel,
                                editingBinding: editingBinding
                            )
                        }
                    }
                    .padding(.vertical, Spacing.xs)
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
            .frame(width: IconSize.sm, height: IconSize.sm)
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
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(Palette.textSecondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(Palette.warning)
            Text(message)
                .font(Typography.callout)
                .multilineTextAlignment(.center)
            Button("Réessayer", action: retry)
                .controlSize(.small)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
