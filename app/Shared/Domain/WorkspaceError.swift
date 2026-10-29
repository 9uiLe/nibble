import Foundation

enum WorkspaceError: Error, Equatable, Sendable {
    case unavailable
    case readOnly
    case storage(code: Int32)
    case unsupportedSchema
    case corruptData
    case missingCard
    case missingDraft
    case conflict
    case staleCheckpoint
    case invalidDraft
    case emptyBody
    case emptyTitle
    case missingValues([String])

    static func normalize(_ error: any Error) -> Self {
        error as? Self ?? .unavailable
    }
}
