import Core
import Foundation

/// Wire-format DTO for a `PATCH /lists/{listID}/tasks/{taskID}` body.
///
/// Custom `encode(to:)` so that each ``Patch`` field maps to one of three
/// JSON outcomes: absent key (`.unchanged`), explicit `null`
/// (`.set(nil)`), or the value (`.set(value)`). The default synthesised
/// `Encodable` cannot express the "present but null" case.
struct RemoteTaskPatch: Encodable {
    let title: Patch<String>
    let notes: Patch<String>
    let due: Patch<Date>
    let status: Patch<TaskStatus>

    init(patch: TaskPatch) {
        title = patch.title
        notes = patch.notes
        due = patch.due
        status = patch.status
    }

    private enum CodingKeys: String, CodingKey {
        case title, notes, due, status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encodeIfChanged(title, forKey: .title, in: &container)
        try Self.encodeIfChanged(notes, forKey: .notes, in: &container)
        try Self.encodeIfChanged(due, forKey: .due, in: &container)
        try Self.encodeStatusIfChanged(status, in: &container)
    }

    private static func encodeIfChanged(
        _ patch: Patch<some Encodable>,
        forKey key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch patch {
        case .unchanged:
            return
        case .set(nil):
            try container.encodeNil(forKey: key)
        case let .set(.some(value)):
            try container.encode(value, forKey: key)
        }
    }

    private static func encodeStatusIfChanged(
        _ patch: Patch<TaskStatus>,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch patch {
        case .unchanged:
            return
        case .set(nil):
            try container.encodeNil(forKey: .status)
        case let .set(.some(value)):
            // `TaskStatus.rawValue` is the exact wire string Google expects.
            try container.encode(value.rawValue, forKey: .status)
        }
    }
}
