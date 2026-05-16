import Foundation

/// Wire-format DTO for `POST /users/@me/lists` and
/// `PATCH /users/@me/lists/{listID}` bodies.
///
/// Lists expose only `title` as a mutable field — Google manages
/// `updated` and the list-level ordering itself, and the REST API
/// rejects any other key in the body. A single struct covers both
/// create and rename.
struct RemoteTaskListInput: Encodable {
    let title: String
}
