import Core
import Foundation
import GoogleAuth
import GoogleTasksClient

/// Read path for ``TasksViewModel``: fetches lists + tasks for the
/// current selection, drives the polling loop and the aggregated-mode
/// fan-out. Lives in its own extension file so the main type stays
/// under the SwiftLint per-file and per-class line budgets — the P5
/// mutation path lives in [`TasksViewModel+Mutations.swift`](TasksViewModel+Mutations.swift).
///
/// Concurrency contract:
///
/// - All entry points (``reload``, ``reloadSingle``, ``reloadAll``,
///   ``loadTasks``) run on the main actor.
/// - The aggregated `withTaskGroup` fan-out hops off the actor to
///   parallelise per-account fetches, and re-enters when storing the
///   final slices into `state`.
/// - Every async path checks ``generation`` before mutating state so
///   a selection change mid-flight discards stale results.
extension TasksViewModel {
    // MARK: - Reload

    func reload(forceReload: Bool, fromUser: Bool = false) async {
        let generation = UUID()
        self.generation = generation

        switch selection {
        case .none:
            state = .idle
            return

        case let .single(accountID):
            await reloadSingle(accountID: accountID, generation: generation, forceReload: forceReload, fromUser: fromUser)

        case let .all(ids):
            await reloadAll(accountIDs: ids, generation: generation, forceReload: forceReload, fromUser: fromUser)
        }

        startAutoRefreshIfNeeded()
    }

    // MARK: - Single-mode loading

    func reloadSingle(
        accountID: AccountID,
        generation: UUID,
        forceReload: Bool,
        fromUser: Bool
    ) async {
        guard let account = accountLookup(accountID) else {
            // Account vanished between setSelection and reload (e.g. just
            // got removed). Snap back to idle and let the panel react.
            state = .idle
            return
        }

        // Keep the previous payload visible during a manual refresh so
        // the panel doesn't flash to a spinner.
        if fromUser, case var .singleLoaded(existing) = state {
            isRefreshing = true
            existing.account = account
            state = .singleLoaded(existing)
        } else {
            state = .loading
        }

        defer { if fromUser { isRefreshing = false } }

        let client = sessions.client(for: accountID)
        do {
            let lists = try await client.fetchTaskLists(forceReload: forceReload)
            persistLists(lists, accountID: accountID)
            guard self.generation == generation else { return }

            guard !lists.isEmpty else {
                state = .singleLoaded(SinglePayload(
                    account: account,
                    lists: [],
                    selectedListID: nil,
                    tasksState: .loaded([])
                ))
                return
            }

            let preservedListID = currentlySelectedSingleListID
            let selection: String = {
                if let preservedListID, lists.contains(where: { $0.id == preservedListID }) {
                    return preservedListID
                }
                return lists[0].id
            }()

            state = .singleLoaded(SinglePayload(
                account: account,
                lists: lists,
                selectedListID: selection,
                tasksState: .loading
            ))

            // Warm the cache for every list so subsequent list-switches
            // are instant. Errors here are swallowed individually — a
            // failure on one list must not block the others.
            await preloadTasks(client: client, lists: lists, forceReload: forceReload, generation: generation)
            guard self.generation == generation else { return }

            await loadTasks(accountID: accountID, listID: selection, generation: generation, forceReload: false)
        } catch {
            guard self.generation == generation else { return }
            state = .error(Self.messageFor(error))
        }
    }

    func loadTasks(accountID: AccountID, listID: String, generation: UUID, forceReload: Bool) async {
        let client = sessions.client(for: accountID)
        let showsCompleted = showsCompleted

        // Fast path: cache hit → swap directly, no loading flash.
        if !forceReload, let cached = await client.cachedTasks(for: listID, showCompleted: showsCompleted) {
            guard self.generation == generation else { return }
            guard case var .singleLoaded(payload) = state, payload.selectedListID == listID else { return }
            payload.tasksState = .loaded(cached)
            state = .singleLoaded(payload)
            return
        }

        if case var .singleLoaded(payload) = state, payload.selectedListID == listID {
            payload.tasksState = .loading
            state = .singleLoaded(payload)
        }

        do {
            let tasks = try await client.fetchTasks(
                in: listID,
                showCompleted: showsCompleted,
                forceReload: forceReload
            )
            // Persist the just-fetched view so the next launch can
            // hydrate without a network round-trip. The
            // `showsCompleted`-driven subset is acceptable: the next
            // sync rewrites the cache anyway, and a missing completed
            // task in the cold-start cache is preferable to a stale
            // "still incomplete" row that the user already ticked off.
            persistTasks(tasks, listID: listID, accountID: accountID)
            guard self.generation == generation else { return }
            guard case var .singleLoaded(payload) = state, payload.selectedListID == listID else { return }
            payload.tasksState = .loaded(tasks)
            state = .singleLoaded(payload)
        } catch {
            guard self.generation == generation else { return }
            guard case var .singleLoaded(payload) = state, payload.selectedListID == listID else { return }
            payload.tasksState = .error(Self.messageFor(error))
            state = .singleLoaded(payload)
        }
    }

    private func preloadTasks(
        client: GoogleTasksClient,
        lists: [TaskList],
        forceReload: Bool,
        generation: UUID
    ) async {
        let showsCompleted = showsCompleted
        await withTaskGroup(of: Void.self) { group in
            for list in lists {
                let listID = list.id
                group.addTask {
                    _ = try? await client.fetchTasks(
                        in: listID,
                        showCompleted: showsCompleted,
                        forceReload: forceReload
                    )
                }
            }
        }
        _ = generation // generation captured here only as documentation
    }

    var currentlySelectedSingleListID: String? {
        if case let .singleLoaded(payload) = state { return payload.selectedListID }
        return nil
    }

    // MARK: - Aggregated-mode loading

    func reloadAll(
        accountIDs: [AccountID],
        generation: UUID,
        forceReload: Bool,
        fromUser: Bool
    ) async {
        // Filter to accounts we can resolve right now. An id whose
        // ``accountLookup`` returns `nil` was just removed. Forwarded
        // through an explicit closure rather than passed by reference:
        // Swift 6.0 cannot prove that a `@MainActor` function reference
        // is non-throwing when it lands in `Array.compactMap`'s
        // `rethrows` slot, even though the call site is itself on the
        // main actor.
        let resolved: [Account] = accountIDs.compactMap { accountLookup($0) }

        guard !resolved.isEmpty else {
            state = .idle
            return
        }

        if fromUser, case .allLoaded = state {
            isRefreshing = true
        } else {
            state = .loading
        }
        defer { if fromUser { isRefreshing = false } }

        let showsCompleted = showsCompleted
        let sessions = sessions

        let sections: [AccountSection] = await withTaskGroup(of: AccountSection?.self) { group in
            for account in resolved {
                let client = sessions.client(for: account.id)
                group.addTask {
                    await Self.section(
                        for: account,
                        client: client,
                        showsCompleted: showsCompleted,
                        forceReload: forceReload
                    )
                }
            }
            var out: [AccountID: AccountSection] = [:]
            for await section in group {
                if let section { out[section.account.id] = section }
            }
            // Preserve user-display order.
            return resolved.compactMap { out[$0.id] }
        }

        guard self.generation == generation else { return }
        state = .allLoaded(sections)

        // Persist the aggregated payload — best-effort, fire-and-forget.
        // Done after assigning state so the UI never waits on disk I/O.
        for section in sections {
            let accountID = section.account.id
            var loadedLists: [TaskList] = []
            for slice in section.slices {
                loadedLists.append(slice.list)
                if case let .loaded(tasks) = slice.tasksState {
                    persistTasks(tasks, listID: slice.list.id, accountID: accountID)
                }
            }
            persistLists(loadedLists, accountID: accountID)
        }
    }

    /// Fetches lists + tasks for one account. Errors on individual lists
    /// surface inside the section so the rest of the aggregated view
    /// keeps rendering.
    private static func section(
        for account: Account,
        client: GoogleTasksClient,
        showsCompleted: Bool,
        forceReload: Bool
    ) async -> AccountSection? {
        let lists: [TaskList]
        do {
            lists = try await client.fetchTaskLists(forceReload: forceReload)
        } catch {
            // Whole account failed to load lists. We still surface a
            // section so the UI shows the user *which* account is in
            // trouble; the per-list error renders in place of tasks.
            let slice = ListSlice(
                list: TaskList(id: "__lists_error__", title: "—", updatedAt: Date()),
                tasksState: .error(messageFor(error))
            )
            return AccountSection(account: account, slices: [slice])
        }

        let slices: [ListSlice] = await withTaskGroup(of: ListSlice.self) { group in
            for list in lists {
                let captured = list
                group.addTask {
                    do {
                        let tasks = try await client.fetchTasks(
                            in: captured.id,
                            showCompleted: showsCompleted,
                            forceReload: forceReload
                        )
                        return ListSlice(list: captured, tasksState: .loaded(tasks))
                    } catch {
                        return ListSlice(list: captured, tasksState: .error(messageFor(error)))
                    }
                }
            }
            var out: [ListSlice] = []
            for await slice in group {
                out.append(slice)
            }
            // Keep Google's lexicographic ordering by `id` — there is
            // no documented ordering for task *lists* themselves, but
            // stable across launches matters more than alphabetical.
            return out.sorted { $0.list.id < $1.list.id }
        }

        return AccountSection(account: account, slices: slices)
    }

    // MARK: - Auto-refresh loop

    func startAutoRefreshIfNeeded() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.autoRefreshInterval)
                } catch {
                    return
                }
                guard let self else { return }
                await reload(forceReload: true, fromUser: false)
            }
        }
    }
}
