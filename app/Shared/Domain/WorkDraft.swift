import Foundation

/// A durable work session is separate from every published card.
struct WorkDraft: Identifiable, Equatable, Sendable {
    enum Target: Equatable, Sendable, Codable {
        case new
        case edit(cardID: UUID, baseVersion: Int)
        case prepare(cardID: UUID, baseVersion: Int)
    }

    let id: UUID
    let target: Target
    private(set) var title: String
    private(set) var body: String
    private(set) var usesVariables: Bool
    private(set) var values: [String: String]
    private(set) var sequence: Int
    private(set) var checkpointSequence: Int
    let modifiedAt: Date

    init(id: UUID = UUID(), target: Target = .new, title: String = "", body: String = "", usesVariables: Bool = false,
         values: [String: String] = [:], sequence: Int = 0, modifiedAt: Date = Date()) {
        self.id = id
        self.target = target
        self.title = title
        self.body = body
        self.usesVariables = usesVariables
        self.values = values
        self.sequence = sequence
        checkpointSequence = sequence
        self.modifiedAt = modifiedAt
    }

    mutating func update(title: String, body: String, values: [String: String], usesVariables: Bool? = nil) throws {
        let nextUsesVariables = usesVariables ?? self.usesVariables
        guard !self.title.utf8.elementsEqual(title.utf8)
            || !self.body.utf8.elementsEqual(body.utf8)
            || !Self.sameValues(self.values, values)
            || self.usesVariables != nextUsesVariables else { return }
        guard sequence >= 0, sequence < Int.max - 1 else { throw WorkspaceError.invalidDraft }
        self.title = title
        self.body = body
        self.usesVariables = nextUsesVariables
        self.values = values
        sequence += 1
    }

    func renderedBody() throws -> String {
        guard usesVariables else { return body }
        return try TextTemplate(body).render(values: values)
    }

    mutating func acknowledgeCheckpoint(_ retained: WorkDraft) {
        guard retained.id == id, retained.target == target, retained.sequence <= sequence else { return }
        checkpointSequence = max(checkpointSequence, retained.sequence)
    }

    var cardID: UUID? {
        switch target {
        case .new: nil
        case .edit(let cardID, _), .prepare(let cardID, _): cardID
        }
    }

    var baseVersion: Int? {
        switch target {
        case .new: nil
        case .edit(_, let baseVersion), .prepare(_, let baseVersion): baseVersion
        }
    }

    var isPreparation: Bool {
        if case .prepare = target { return true }
        return false
    }

    func hasSameInput(as other: Self) -> Bool {
        target == other.target && title.utf8.elementsEqual(other.title.utf8)
            && body.utf8.elementsEqual(other.body.utf8) && usesVariables == other.usesVariables
            && Self.sameValues(values, other.values)
    }

    private static func sameValues(_ first: [String: String], _ second: [String: String]) -> Bool {
        guard first.count == second.count else { return false }
        return first.allSatisfy { key, value in
            guard let candidate = second[key] else { return false }
            return value.utf8.elementsEqual(candidate.utf8)
        }
    }
}
