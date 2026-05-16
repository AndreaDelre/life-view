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
    /// Skipped when the parent renders a single account (the bar already
    /// shows which profile is selected — repeating the avatar + name +
    /// email would only add clutter).
    var showsHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if showsHeader {
                header
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
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

/// Modern collapsible list section. Click the header to fold the rows
/// underneath; the chevron rotates 90° on collapse to reinforce the
/// state visually. Mirrors the section-header treatment used by
/// Todoist / TickTick: chevron + title + count chip.
struct ListSliceView: View {
    let slice: TasksViewModel.ListSlice
    let accountID: AccountID
    @Bindable var viewModel: TasksViewModel
    let editingBinding: (String) -> Binding<Bool>

    /// Open by default — power-users open the panel to triage tasks,
    /// not to choose which list to expand. Per-list collapse state is
    /// intentionally local (no persistence) because the panel session
    /// is short-lived and a sticky collapse would surprise users who
    /// open the panel expecting all their tasks.
    @State private var isCollapsed: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            // Inner wrapper is the clip region: as the VStack collapses,
            // the `.move(edge: .top)` transition slides the content up
            // and the wrapper's `.clipped()` hides everything that
            // crosses its top edge — so the tasks disappear *behind*
            // the header instead of fading over it. Outer spacing is
            // 0 (top padding lives on the content) so the closed state
            // doesn't leave a phantom gap below the header.
            VStack(alignment: .leading, spacing: 0) {
                if !isCollapsed {
                    content
                        .padding(.leading, Spacing.xs)
                        .padding(.top, Spacing.xs)
                        .transition(reduceMotion ? .opacity : .move(edge: .top))
                }
            }
            .clipped()
        }
        .animation(reduceMotion ? Motion.reduced : Motion.standard, value: isCollapsed)
    }

    /// Top header row: chevron + title + count chip. Tapping anywhere
    /// on the row toggles the section. Hidden behind a borderless
    /// button so the whole strip is one hit-target with the right
    /// VoiceOver semantics (button + expanded/collapsed state).
    private var sectionHeader: some View {
        Button {
            isCollapsed.toggle()
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.textSecondary)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .frame(width: 12, alignment: .center)
                    .accessibilityHidden(true)

                Text(slice.list.title)
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Palette.textPrimary)

                if let total = visibleCount {
                    CountBadge(count: total)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slice.list.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Active pour \(isCollapsed ? "déplier" : "replier") la liste")
        .accessibilityAddTraits(.isHeader)
    }

    /// Count rendered in the badge. Returns `nil` while loading / on
    /// error so we don't show a transient "0".
    private var visibleCount: Int? {
        guard case let .loaded(tasks) = slice.tasksState else { return nil }
        return tasks.count
    }

    private var accessibilityValue: String {
        let state = isCollapsed ? "replié" : "déplié"
        if let count = visibleCount {
            return "\(state), \(count) tâche\(count > 1 ? "s" : "")"
        }
        return state
    }

    @ViewBuilder
    private var content: some View {
        switch slice.tasksState {
        case .loading:
            HStack { ProgressView().controlSize(.small)
                Spacer()
            }
            .accessibilityLabel("Chargement des tâches de \(slice.list.title)")
        case let .error(message):
            Text(message)
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
        case let .loaded(tasks):
            if tasks.isEmpty {
                Text("Aucune tâche")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityLabel("Aucune tâche dans \(slice.list.title)")
            } else {
                tasksStack(tasks)
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
        let entries = TaskHierarchy.entries(for: tasks)
        return VStack(spacing: 0) {
            ForEach(entries) { entry in
                TaskRowView(
                    task: entry.task,
                    isPending: viewModel.isPending(taskID: entry.task.id),
                    depth: entry.depth,
                    totalSubtasks: entry.totalSubtasks,
                    completedSubtasks: entry.completedSubtasks,
                    isEditing: editingBinding(entry.task.id),
                    onToggleCompletion: { isCompleted in
                        viewModel.setCompletion(
                            isCompleted,
                            for: entry.task.id,
                            in: slice.list.id,
                            account: accountID
                        )
                    },
                    onEditTitle: { newTitle in
                        viewModel.editTaskTitle(
                            newTitle,
                            for: entry.task.id,
                            in: slice.list.id,
                            account: accountID
                        )
                    },
                    onDelete: {
                        viewModel.deleteTask(
                            taskID: entry.task.id,
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
