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
        var components = URLComponents(url: base.appendingPathComponent("users/@me/lists"), resolvingAgainstBaseURL: false)
        // Force-unwrap is fine: we just constructed the URL above from a
        // hard-coded base — `URLComponents(url:)` can only return nil for
        // URLs that aren't representable as components, which doesn't
        // apply here.
        // swiftlint:disable:next force_unwrapping
        var resolved = components!
        var items: [URLQueryItem] = [URLQueryItem(name: "maxResults", value: "100")]
        if let pageToken {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        resolved.queryItems = items
        // swiftlint:disable:next force_unwrapping
        return resolved.url!
    }

    /// `GET /lists/{listID}/tasks`
    ///
    /// `showCompleted=false` mirrors the default visibility of
    /// `tasks.google.com` — completed tasks are hidden until the user
    /// flips the toggle. P3 has no toggle yet; we'll surface it in P6.
    static func tasks(in listID: String, pageToken: String?) -> URL {
        let escapedID = listID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listID
        // swiftlint:disable:next force_unwrapping
        var components = URLComponents(url: base.appendingPathComponent("lists/\(escapedID)/tasks"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "showCompleted", value: "false"),
            URLQueryItem(name: "showHidden", value: "false"),
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
