import Foundation

/// Google Tasks REST v1 endpoints used by ``GoogleTasksClient``.
///
/// Reference: https://developers.google.com/tasks/reference/rest
enum GoogleTasksEndpoints {
    // swiftlint:disable force_unwrapping
    // Hard-coded HTTPS literals — `URL(string:)` cannot fail here.
    static let base = URL(string: "https://tasks.googleapis.com/tasks/v1")!
    // swiftlint:enable force_unwrapping

    /// `GET /users/@me/lists`
    static func taskLists(pageToken: String?) -> URL {
        // Force-unwraps are fine: we just constructed the URL from a
        // hard-coded HTTPS base, and `URLComponents(url:)` only returns
        // nil for URLs that aren't representable as components.
        // swiftlint:disable force_unwrapping
        var components = URLComponents(url: base.appendingPathComponent("users/@me/lists"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [URLQueryItem(name: "maxResults", value: "100")]
        if let pageToken {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = items
        return components.url!
        // swiftlint:enable force_unwrapping
    }

    /// `GET /lists/{listID}/tasks`
    ///
    /// When `showCompleted` is true, Google also returns hidden tasks
    /// (`showHidden=true`) — that mirrors what `tasks.google.com` does
    /// when its "Afficher les tâches terminées" toggle is on. We keep
    /// `showDeleted=false` either way: tombstones aren't useful in the UI.
    static func tasks(in listID: String, pageToken: String?, showCompleted: Bool) -> URL {
        let escapedID = listID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listID
        // swiftlint:disable:next force_unwrapping
        var components = URLComponents(url: base.appendingPathComponent("lists/\(escapedID)/tasks"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "showCompleted", value: showCompleted ? "true" : "false"),
            URLQueryItem(name: "showHidden", value: showCompleted ? "true" : "false"),
            URLQueryItem(name: "showDeleted", value: "false")
        ]
        if let pageToken {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = items
        // swiftlint:disable:next force_unwrapping
        return components.url!
    }

    /// `POST /lists/{listID}/tasks` — body is a ``RemoteTaskInput``.
    static func insertTask(in listID: String) -> URL {
        let escapedID = listID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listID
        return base.appendingPathComponent("lists/\(escapedID)/tasks")
    }

    /// `PATCH /lists/{listID}/tasks/{taskID}` — body is a ``RemoteTaskPatch``.
    static func updateTask(in listID: String, taskID: String) -> URL {
        let escapedList = listID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listID
        let escapedTask = taskID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskID
        return base.appendingPathComponent("lists/\(escapedList)/tasks/\(escapedTask)")
    }

    /// `DELETE /lists/{listID}/tasks/{taskID}` — no body, expected 204.
    static func deleteTask(in listID: String, taskID: String) -> URL {
        updateTask(in: listID, taskID: taskID)
    }

    /// `POST /users/@me/lists` — body is a ``RemoteTaskListInput``.
    static func insertTaskList() -> URL {
        base.appendingPathComponent("users/@me/lists")
    }

    /// `PATCH /users/@me/lists/{listID}` — body is a ``RemoteTaskListInput``.
    /// Used to rename a list; `title` is the only mutable field.
    static func updateTaskList(listID: String) -> URL {
        let escapedID = listID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listID
        return base.appendingPathComponent("users/@me/lists/\(escapedID)")
    }

    /// `DELETE /users/@me/lists/{listID}` — no body, expected 204. Deletes
    /// the list and every task it contains (server-side cascade).
    static func deleteTaskList(listID: String) -> URL {
        updateTaskList(listID: listID)
    }
}
