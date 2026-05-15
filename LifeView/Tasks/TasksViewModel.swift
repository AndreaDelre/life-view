import Core
import Foundation
import GoogleTasksClient
import Observation

/// Drives the tasks corner of the panel. Single state machine: load the
/// task lists once, then load + display the tasks of the selected list.
///
/// Lives on the main actor because every transition feeds the SwiftUI
/// view tree directly. The underlying ``GoogleTasksClient`` is an actor,
/// so its calls suspend without blocking the main thread.
@MainActor
@Observable
final class TasksViewModel {
    enum TasksState: Equatable {
        case loading
        case loaded([TaskItem])
        case error(String)
    }

    struct Payload: Equatable {
        var lists: [TaskList]
        var selectedListID: String?
        var tasksState: TasksState
    }

    enum State: Equatable {
        case idle
        case loading
        case loaded(Payload)
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var isRefreshing: Bool = false

    private let client: GoogleTasksClient

    /// Identifier of the in-flight tasks fetch. Used to drop responses
    /// from a previous list when the user switches lists faster than the
    /// network responds — without this, a slow first request can land
    /// after a quick second one and clobber the displayed payload.
    private var currentTasksFetch: UUID?

    init(client: GoogleTasksClient) {
        self.client = client
    }

    // MARK: - Lifecycle

    /// Idempotent first-run trigger. Loads task lists if the view-model
    /// is still in `.idle`; otherwise it's a no-op (the view re-appearing
    /// after a panel hide should not re-fetch).
    func start() async {
        guard case .idle = state else { return }
        await loadLists(forceReload: false)
    }

    /// Pull-to-refresh handler. Always re-fetches the lists AND the tasks
    /// of the currently selected list, bypassing the cache.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let previouslySelected = currentlySelectedListID
        await loadLists(forceReload: true, preservingSelection: previouslySelected)
    }

    /// Resets to `.idle` and drops the cache. Called when the user signs
    /// out so a subsequent sign-in starts from a clean slate.
    func reset() async {
        state = .idle
        currentTasksFetch = nil
        await client.invalidateCache()
    }

    /// Switches to a different task list. Cached tasks are surfaced
    /// instantly; if absent, the per-list state moves to `.loading` and
    /// fetches.
    func selectList(_ listID: String) {
        guard case .loaded(var payload) = state else { return }
        guard payload.selectedListID != listID else { return }
        guard payload.lists.contains(where: { $0.id == listID }) else { return }

        payload.selectedListID = listID
        payload.tasksState = .loading
        state = .loaded(payload)

        Task { await loadTasks(for: listID, forceReload: false) }
    }

    // MARK: - Internal flows

    private var currentlySelectedListID: String? {
        if case .loaded(let payload) = state { return payload.selectedListID }
        return nil
    }

    private func loadLists(forceReload: Bool, preservingSelection: String? = nil) async {
        if !forceReload, case .idle = state {
            state = .loading
        }

        do {
            let lists = try await client.fetchTaskLists(forceReload: forceReload)
            guard !lists.isEmpty else {
                state = .loaded(Payload(lists: [], selectedListID: nil, tasksState: .loaded([])))
                return
            }

            let nextSelection: String = {
                if let preservingSelection, lists.contains(where: { $0.id == preservingSelection }) {
                    return preservingSelection
                }
                return lists[0].id
            }()

            state = .loaded(Payload(
                lists: lists,
                selectedListID: nextSelection,
                tasksState: .loading
            ))
            await loadTasks(for: nextSelection, forceReload: forceReload)
        } catch {
            state = .error(Self.message(for: error))
        }
    }

    private func loadTasks(for listID: String, forceReload: Bool) async {
        let fetchID = UUID()
        currentTasksFetch = fetchID

        do {
            let tasks = try await client.fetchTasks(in: listID, forceReload: forceReload)
            // Late response from a prior list — discard.
            guard currentTasksFetch == fetchID else { return }
            guard case .loaded(var payload) = state, payload.selectedListID == listID else { return }
            payload.tasksState = .loaded(tasks)
            state = .loaded(payload)
        } catch {
            guard currentTasksFetch == fetchID else { return }
            guard case .loaded(var payload) = state, payload.selectedListID == listID else { return }
            payload.tasksState = .error(Self.message(for: error))
            state = .loaded(payload)
        }
    }

    // MARK: - Helpers

    private static func message(for error: Error) -> String {
        if let tasksError = error as? GoogleTasksError {
            switch tasksError {
            case .unauthorized: return "Session Google expirée. Reconnecte-toi."
            case .http(let status): return "Erreur Google Tasks (HTTP \(status))."
            case .decodingFailed: return "Réponse Google inattendue."
            case .transport(let message): return "Problème réseau : \(message)"
            }
        }
        return (error as NSError).localizedDescription
    }
}
