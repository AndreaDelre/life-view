import Core
import SwiftUI

/// Root view of the tasks corner: list picker on top, scrollable list of
/// tasks below. Owns nothing — purely a presentation layer over
/// ``TasksViewModel``.
struct TasksView: View {
    @Bindable var viewModel: TasksViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewModel.state {
            case .idle, .loading:
                loadingPlaceholder
            case .error(let message):
                ErrorState(message: message) {
                    Task { await viewModel.refresh() }
                }
            case .loaded(let payload):
                loadedContent(payload)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await viewModel.start()
        }
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func loadedContent(_ payload: TasksViewModel.Payload) -> some View {
        if payload.lists.isEmpty {
            EmptyState(
                icon: "tray",
                title: "Aucune liste",
                message: "Ce compte Google n'a pas encore de liste de tâches."
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                listPicker(payload)
                Divider()
                tasksSection(payload)
            }
        }
    }

    private func listPicker(_ payload: TasksViewModel.Payload) -> some View {
        let selectionBinding = Binding<String>(
            get: { payload.selectedListID ?? payload.lists.first?.id ?? "" },
            set: { viewModel.selectList($0) }
        )

        return Picker("Liste", selection: selectionBinding) {
            ForEach(payload.lists) { list in
                Text(list.title).tag(list.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.regular)
    }

    @ViewBuilder
    private func tasksSection(_ payload: TasksViewModel.Payload) -> some View {
        switch payload.tasksState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ErrorState(message: message) {
                Task { await viewModel.refresh() }
            }
        case .loaded(let tasks):
            if tasks.isEmpty {
                EmptyState(
                    icon: "checkmark.seal",
                    title: "Tout est fait !",
                    message: "Aucune tâche ouverte dans cette liste."
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

    // MARK: - Placeholders

    private var loadingPlaceholder: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
