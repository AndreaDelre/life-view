import Core
import SwiftUI

/// Root view of the tasks corner.
///
/// Two rendering paths driven by ``TasksViewModel/state``:
///
/// - Single mode: list picker on top, scrollable tasks below — same shape
///   as P3 plus account context.
/// - All-accounts mode: a single scrollable view with one section per
///   account, each section listing every list with its tasks underneath.
struct TasksView: View {
    @Bindable var viewModel: TasksViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewModel.state {
            case .idle, .loading:
                loadingPlaceholder
            case .error(let message):
                ErrorState(message: message) { Task { await viewModel.refresh() } }
            case .singleLoaded(let payload):
                singleContent(payload)
            case .allLoaded(let sections):
                allContent(sections)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        case .error(let message):
            ErrorState(message: message) { Task { await viewModel.refresh() } }
        case .loaded(let tasks):
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
                List {
                    ForEach(tasks) { task in
                        TaskRowView(task: task)
                            .listRowSeparator(.visible)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.refresh() }
            }
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
                            AccountSectionView(section: section)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ForEach(section.slices) { slice in
                ListSliceView(slice: slice)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(slice.list.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.leading, 4)
            switch slice.tasksState {
            case .loading:
                HStack { ProgressView().controlSize(.small); Spacer() }
                    .padding(.leading, 4)
            case .error(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            case .loaded(let tasks):
                if tasks.isEmpty {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(tasks) { task in
                            TaskRowView(task: task)
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
