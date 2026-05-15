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
}
