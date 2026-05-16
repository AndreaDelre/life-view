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
    @Bindable var accountsViewModel: AccountsViewModel
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
        .background(shortcutHosts)
        // Notification-driven focus: when ``focusRequestTaskID`` is
        // non-nil, mirror it into the local selection state and clear
        // it. The actual scroll-to happens inside the per-mode list
        // via `.scrollPosition` (single mode uses `List`'s built-in
        // selection-tracking, so just setting `selectedTaskID` is
        // enough to highlight + scroll).
        .onChange(of: viewModel.focusRequestTaskID) { _, requested in
            guard let requested else { return }
            selectedTaskID = requested
            viewModel.focusRequestTaskID = nil
        }
    }

    /// All the "invisible" buttons that exist solely to host a
    /// `keyboardShortcut`. Grouped here so the body stays readable and
    /// the binding/label mapping lives next to ``Shortcut`` rather than
    /// scattered through the view tree.
    private var shortcutHosts: some View {
        ZStack {
            // ⌘N — historical alternate for the new-task field focus.
            // Kept alongside `N` because muscle memory from other
            // task apps reaches for the modified form.
            Button("Nouvelle tâche", action: focusNewTaskField)
                .keyboardShortcut("n", modifiers: .command)
                .hiddenShortcutHost()

            // N — focus the new-task field. Bare letter (no modifier);
            // safe because it only fires when the panel has focus and
            // no `TextField` is editing — SwiftUI gives focused fields
            // priority on plain-letter keys.
            Button("Nouvelle tâche", action: focusNewTaskField)
                .keyboardShortcut(Shortcut.newTask)
                .hiddenShortcutHost()

            // ⌘1 … ⌘9 — switch to the Nth list of the current account.
            // We bind all nine even if the account has fewer lists:
            // the action no-ops past the end and the menu reflects
            // reality. Aggregated mode silently ignores all nine
            // because there is no current list there.
            ForEach(1...9, id: \.self) { index in
                Button("Liste \(index)", action: { selectList(at: index - 1) })
                    .keyboardShortcut(Shortcut.switchList(index))
                    .hiddenShortcutHost()
            }

            // ⌘⇧A — cycle to the next account.
            Button("Compte suivant", action: cycleAccount)
                .keyboardShortcut(Shortcut.cycleAccount)
                .hiddenShortcutHost()
        }
    }

    private func focusNewTaskField() {
        guard case .singleLoaded = viewModel.state else { return }
        newTaskFieldFocused = true
    }

    /// Switches to the Nth list of the current single-mode account.
    /// No-op in aggregated mode (every list is already on screen) or
    /// when the index falls past the end of the list collection.
    private func selectList(at index: Int) {
        guard case let .singleLoaded(payload) = viewModel.state else { return }
        guard index >= 0, index < payload.lists.count else { return }
        viewModel.selectList(payload.lists[index].id)
    }

    /// Cycles to the next account in display order. In aggregated mode
    /// we bounce to the first account in single mode — the user gets a
    /// concrete selection rather than "wrapping inside the aggregate"
    /// which has no meaning. If there is only one account, no-op.
    private func cycleAccount() {
        let accounts = accountsViewModel.accounts
        guard accounts.count >= 1 else { return }
        switch accountsViewModel.mode {
        case .all:
            accountsViewModel.setMode(.single)
            Task { await accountsViewModel.select(accounts[0].id) }
        case .single:
            guard accounts.count >= 2 else { return }
            let currentIndex = accountsViewModel.selectedID
                .flatMap { id in accounts.firstIndex(where: { $0.id == id }) } ?? -1
            let next = accounts[(currentIndex + 1) % accounts.count]
            Task { await accountsViewModel.select(next.id) }
        }
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
            VStack(alignment: .leading, spacing: Spacing.md) {
                singleToolbar(payload)
                NewTaskRow(
                    title: $newTaskTitle,
                    due: $newTaskDue,
                    fieldFocused: $newTaskFieldFocused,
                    onSubmit: submitNewTask
                )
                singleTasksSection(payload)
            }
        }
    }

    // `singleToolbar`, `listTitleMenu` and `listActionsMenu` live in
    // `TasksView+SingleToolbar.swift`. The list CRUD prompts (create /
    // rename / delete) live in `TasksView+ListActions.swift`. Both
    // splits keep this file under the SwiftLint `file_length` /
    // `type_body_length` budgets.

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

    @discardableResult
    private func deleteSelected(listID: String, accountID: AccountID) -> KeyPress.Result {
        guard let id = selectedTaskID else { return .ignored }
        viewModel.deleteTask(taskID: id, in: listID, account: accountID)
        selectedTaskID = nil
        return .handled
    }

    /// One row inside the single-mode `List`. Extracted from
    /// ``singleTasksList(tasks:accountID:listID:)`` so the parent stays
    /// within SwiftLint's function-body budget — every captured value
    /// is already a local, so the split is purely syntactic.
    private func singleTaskRow(
        entry: TaskHierarchyEntry,
        accountID: AccountID,
        listID: String
    ) -> some View {
        TaskRowView(
            task: entry.task,
            isPending: viewModel.isPending(taskID: entry.task.id),
            depth: entry.depth,
            totalSubtasks: entry.totalSubtasks,
            completedSubtasks: entry.completedSubtasks,
            isEditing: editingBinding(for: entry.task.id),
            onToggleCompletion: { isCompleted in
                viewModel.setCompletion(isCompleted, for: entry.task.id, in: listID, account: accountID)
            },
            onEditTitle: { newTitle in
                viewModel.editTaskTitle(newTitle, for: entry.task.id, in: listID, account: accountID)
            },
            onDelete: {
                viewModel.deleteTask(taskID: entry.task.id, in: listID, account: accountID)
            }
        )
        .tag(entry.task.id)
        .listRowSeparator(.visible)
        // Block drag on sub-tasks: the move API needs a `parent`
        // argument to keep the row attached to its parent, and the
        // cross-level promote/demote UX is a separate issue. Leaving
        // the handle active would let a drop end up at root level and
        // silently flatten the hierarchy.
        .moveDisabled(entry.depth > 0)
    }

    private func singleTasksList(
        tasks: [TaskItem],
        accountID: AccountID,
        listID: String
    ) -> some View {
        // Flatten the parent/child hierarchy into one annotated array.
        // The order is preserved (Google Tasks returns sub-tasks already
        // interleaved by `position`) so a top-level `List`/`ForEach`
        // still walks the rows in the right order — we only add the
        // `depth` + sub-task counters that the row needs to render
        // itself.
        let entries = TaskHierarchy.entries(for: tasks)
        // Single-mode uses `List` (for native selection + swipe + keyboard
        // handling), which doesn't honour per-row `.transition(...)`
        // modifiers — it has its own insert/remove choreography. We
        // therefore drive the animation at the container level via
        // `.animation(_, value: tasks.map(\.id))`, which is what
        // `List` actually observes to schedule its built-in
        // fade/slide. The aggregated mode below, which uses
        // `LazyVStack`, can apply the richer custom `.transition`.
        return List(selection: $selectedTaskID) {
            ForEach(entries) { entry in
                singleTaskRow(entry: entry, accountID: accountID, listID: listID)
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
        // failure anyway. We listen for both `.delete` (forward delete
        // key) and `.deleteForward` so ⌫ / fn+⌫ both work. ⌘⌫ is
        // intercepted via a dedicated hidden button below to avoid
        // clashing with the List's native row-delete intercept.
        .onKeyPress(.delete) {
            deleteSelected(listID: listID, accountID: accountID)
        }
        .background(
            Button("Supprimer", action: { _ = deleteSelected(listID: listID, accountID: accountID) })
                .keyboardShortcut(.delete, modifiers: .command)
                .hiddenShortcutHost()
        )
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
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text("Tous les comptes")
                        .font(Typography.titleHero)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    CompletedToggle(showsCompleted: viewModel.showsCompleted) {
                        viewModel.toggleShowsCompleted()
                    }
                    RefreshButton(isRefreshing: viewModel.isRefreshing) {
                        Task { await viewModel.refresh() }
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.xl) {
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

// Shared visual primitives (CompletedToggle, RefreshButton, EmptyState,
// ErrorState, hiddenShortcutHost) live in `TasksViewSupport.swift` to
// keep this file under the SwiftLint file-length budget.
