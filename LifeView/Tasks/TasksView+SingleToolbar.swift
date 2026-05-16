import Core
import DesignSystem
import GoogleAuth
import SwiftUI

/// Single-mode toolbar: hero list title, open-task count badge,
/// completed-toggle, refresh, and a trailing `⋯` menu carrying the
/// destructive list actions (rename / delete).
///
/// Extracted from `TasksView.swift` to keep that view under SwiftLint's
/// `file_length` / `type_body_length` budgets — every helper here is
/// pure presentation; the mutations are still owned by the view model
/// hosted in the main view.
extension TasksView {
    @ViewBuilder
    func singleToolbar(_ payload: TasksViewModel.SinglePayload) -> some View {
        let selectedList = payload.lists.first(where: { $0.id == payload.selectedListID })
        let openTasksCount = openTasksCount(in: payload)
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            listTitleMenu(payload)

            if let openTasksCount, openTasksCount > 0 {
                CountBadge(count: openTasksCount)
                    .padding(.leading, Spacing.xxs)
            }

            Spacer(minLength: 0)

            CompletedToggle(showsCompleted: viewModel.showsCompleted) {
                viewModel.toggleShowsCompleted()
            }
            RefreshButton(isRefreshing: viewModel.isRefreshing) {
                Task { await viewModel.refresh() }
            }
            listActionsMenu(selectedList: selectedList)
        }
    }

    /// Open-task count for the currently-loaded payload. Returns `nil`
    /// while tasks are loading / errored so the badge stays out of the
    /// header until we have something authoritative to show.
    private func openTasksCount(in payload: TasksViewModel.SinglePayload) -> Int? {
        guard case let .loaded(tasks) = payload.tasksState else { return nil }
        return tasks.filter { $0.status != .completed }.count
    }

    /// Hero list-title rendered as a dropdown menu. Tapping the title
    /// (or its chevron) opens the picker; selected list gets a
    /// checkmark. CRUD on lists is intentionally moved out to the
    /// trailing `⋯` menu so the title reads as a navigation pivot
    /// rather than a settings entry point.
    private func listTitleMenu(_ payload: TasksViewModel.SinglePayload) -> some View {
        let selectedTitle = payload.lists
            .first(where: { $0.id == payload.selectedListID })?.title
            ?? payload.lists.first?.title
            ?? "Listes"

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
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(selectedTitle)
                    .font(Typography.titleHero)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Liste : \(selectedTitle)")
        .accessibilityHint("Change de liste ou crée une nouvelle liste")
    }

    /// Trailing "⋯" menu carrying the destructive list actions
    /// (rename / delete). Hidden when the current list is a stub
    /// (`local-list-…`) — the actions would silently fail because the
    /// list has no server-side id yet.
    @ViewBuilder
    private func listActionsMenu(selectedList: TaskList?) -> some View {
        if let selectedList, !selectedList.id.hasPrefix("local-list-") {
            Menu {
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
            } label: {
                Image(systemName: "ellipsis")
                    .symbolRenderingMode(.hierarchical)
                    .imageScale(.medium)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Actions sur la liste")
            .accessibilityLabel("Actions sur la liste")
            .accessibilityHint("Renommer ou supprimer la liste courante")
        }
    }
}
