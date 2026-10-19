import Foundation

/// A bounded discovery excerpt. Delivery always loads and validates the full card.
struct PreparedCardSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let preview: String
    let version: Int
    let modifiedAt: Date
    let originTitle: String?

    init(id: UUID, title: String, preview: String, version: Int, modifiedAt: Date, originTitle: String?) {
        self.id = id
        self.title = title
        self.preview = preview
        self.version = version
        self.modifiedAt = modifiedAt
        self.originTitle = originTitle
    }
}
