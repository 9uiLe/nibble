import Foundation

enum DraftTarget: Equatable, Sendable {
    case new
    case snippet(UUID)
}

/// A snapshot may replace only input from its own persisted editing session.
struct Draft: Identifiable, Equatable, Sendable {
    enum Replacement { case newer, identical, rejected }

    private enum InputOrder: Equatable, Sendable {
        case serial(Int)
        case exhausted
    }

    struct Checkpoint: Equatable, Sendable {
        let id: UUID
        let target: DraftTarget
        let baseRevision: Int
        let sequence: Int

        func belongsToSameSession(as candidate: Self) -> Bool {
            (id, baseRevision) == (candidate.id, candidate.baseRevision) && target == candidate.target
        }
    }

    let id: UUID
    let target: DraftTarget
    let baseRevision: Int
    private var inputTitle: String
    private var inputBody: String
    private var inputOrder: InputOrder

    var sequence: Int {
        switch inputOrder {
        case .serial(let number): number
        case .exhausted: Int.max
        }
    }

    var canPersistSequence: Bool {
        guard case .serial = inputOrder else { return false }
        return true
    }

    init(id: UUID, target: DraftTarget, baseRevision: Int, title: String, body: String, sequence: Int = 0) {
        self.id = id
        self.target = target
        self.baseRevision = baseRevision
        inputTitle = title
        inputBody = body
        inputOrder = (0..<Int.max).contains(sequence) ? .serial(sequence) : .exhausted
    }

    var title: String {
        get { inputTitle }
        set {
            guard !SnippetText.hasSameBytes(inputTitle, newValue) else { return }
            inputTitle = newValue
            advanceInputOrder()
        }
    }

    var body: String {
        get { inputBody }
        set {
            guard !SnippetText.hasSameBytes(inputBody, newValue) else { return }
            inputBody = newValue
            advanceInputOrder()
        }
    }

    var checkpoint: Checkpoint {
        .init(id: id, target: target, baseRevision: baseRevision, sequence: sequence)
    }

    private mutating func advanceInputOrder() {
        guard case .serial(let number) = inputOrder else { return }
        let (next, overflowed) = number.addingReportingOverflow(1)
        guard !overflowed, next < Int.max else {
            inputOrder = .exhausted
            return
        }
        inputOrder = .serial(next)
    }

    func canAutosave(over previous: Checkpoint) -> Bool {
        canPersistSequence && (0..<Int.max).contains(previous.sequence)
            && sequence > previous.sequence && checkpoint.belongsToSameSession(as: previous)
    }

    func replacement(of previous: Checkpoint, title: String, body: String) -> Replacement {
        guard canPersistSequence, (0..<Int.max).contains(previous.sequence),
              checkpoint.belongsToSameSession(as: previous), sequence >= previous.sequence else { return .rejected }
        if sequence > previous.sequence { return .newer }
        guard SnippetText.hasSameBytes(inputTitle, title), SnippetText.hasSameBytes(inputBody, body) else { return .rejected }
        return .identical
    }

    var isDisposable: Bool {
        guard !inputTitle.isEmpty || !inputBody.isEmpty else { return true }
        guard case .snippet = target else { return false }
        return sequence == 0
    }
}

struct DraftSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let preview: String
    let updatedAt: Date
}
