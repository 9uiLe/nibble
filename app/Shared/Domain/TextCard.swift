import Foundation

struct TextCard: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let usesVariables: Bool
    let version: Int
    let modifiedAt: Date
    let pinned: Bool
    let deletedAt: Date?
    let originTitle: String?

    init(id: UUID = UUID(), title: String, body: String, usesVariables: Bool = false, version: Int = 1,
         modifiedAt: Date = Date(), pinned: Bool = false, deletedAt: Date? = nil,
         originTitle: String? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.usesVariables = usesVariables
        self.version = version
        self.modifiedAt = modifiedAt
        self.pinned = pinned
        self.deletedAt = deletedAt
        self.originTitle = originTitle
    }
}

struct WorkspaceQuery: Equatable, Sendable {
    var query: String
    var pinnedOnly: Bool
    var trash: Bool
    var offset: Int
    var limit: Int

    init(query: String = "", pinnedOnly: Bool = false, trash: Bool = false,
         offset: Int = 0, limit: Int = 50) {
        self.query = query
        self.pinnedOnly = pinnedOnly
        self.trash = trash
        self.offset = offset
        self.limit = limit
    }
}

struct WorkspacePage: Equatable, Sendable {
    let cards: [TextCard]
    let total: Int
    let hasMore: Bool
}
