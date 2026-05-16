import Core
import Foundation

/// Wire-format DTO for a `POST /lists/{listID}/tasks` body.
///
/// `Encodable`-only (the response of an insert is decoded as
/// ``RemoteTask``). Fields with `nil` are omitted from the JSON payload —
/// Google's insert endpoint defaults `status` to `needsAction` and treats
/// omitted optional fields as "unset", which is exactly what we want.
struct RemoteTaskInput: Encodable {
    let title: String
    let notes: String?
    let due: Date?

    init(draft: TaskDraft) {
        title = draft.title
        // Normalise empty strings to `nil`: an empty `notes` is a UI
        // artefact, not a meaningful value to send to Google.
        notes = (draft.notes?.isEmpty == true) ? nil : draft.notes
        due = draft.due
    }
}
