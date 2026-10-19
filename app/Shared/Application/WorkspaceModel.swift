import Foundation
import Observation

@MainActor @Observable
final class WorkspaceModel {
    enum Route: Identifiable {
        case editor(DraftSessionModel)
        case use(UseSessionModel)
        var id: UUID {
            switch self {
            case .editor(let model): model.id
            case .use(let model): model.id
            }
        }
    }

    enum Notice {
        case saved
        case trashed(TextCard)
        case restored
        case pinned(Bool)
    }

    private let storage: any WorkspaceStorage
    private var loadID = UUID()
    private var opening = false
    var hasOpenWork: Bool { route != nil || opening }
    private var query = WorkspaceQuery()
    private(set) var cards: [TextCard] = []
    private(set) var drafts: [WorkDraft] = []
    private(set) var total = 0
    private(set) var hasMore = false
    private(set) var loading = false
    private(set) var error: WorkspaceError?
    var route: Route?
    var notice: Notice?

    init(storage: any WorkspaceStorage) { self.storage = storage }

    func refresh(search: String = "", pinned: Bool = false, trash: Bool = false) async {
        let request = UUID()
        loadID = request
        loading = true
        defer { if request == loadID { loading = false } }
        let next = WorkspaceQuery(query: search, pinnedOnly: pinned, trash: trash)
        if query != next {
            cards = []
            total = 0
            hasMore = false
        }
        query = next
        error = nil
        do {
            async let page = storage.list(query: query)
            async let work = storage.drafts()
            let (result, drafts) = try await (page, work)
            guard request == loadID, !Task.isCancelled else { return }
            cards = result.cards
            total = result.total
            hasMore = result.hasMore
            self.drafts = drafts
            error = nil
        } catch {
            guard request == loadID else { return }
            self.error = WorkspaceError.normalize(error)
        }
    }

    func loadMore() async {
        guard !loading, hasMore else { return }
        loading = true
        let request = loadID
        defer { if request == loadID { loading = false } }
        let next = WorkspaceQuery(query: query.query, pinnedOnly: query.pinnedOnly, trash: query.trash, offset: cards.count)
        do {
            let result = try await storage.list(query: next)
            guard request == loadID, !Task.isCancelled else { return }
            let known = Set(cards.map(\.id))
            cards += result.cards.filter { !known.contains($0.id) }
            total = result.total
            hasMore = result.hasMore
            error = nil
        } catch {
            if request == loadID { self.error = WorkspaceError.normalize(error) }
        }
    }

    func create(title: String = "", body: String = "") async {
        guard !hasOpenWork else { return }
        opening = true
        defer { opening = false }
        do {
            let draft = try await storage.beginDraft(title: title, body: body)
            guard route == nil, !Task.isCancelled else { return }
            route = .editor(DraftSessionModel(draft: draft, storage: storage))
        } catch { self.error = WorkspaceError.normalize(error) }
    }

    func edit(_ card: TextCard) async {
        guard !hasOpenWork else { return }
        opening = true
        defer { opening = false }
        do {
            let draft = try await storage.editingDraft(cardID: card.id)
            guard route == nil, !Task.isCancelled else { return }
            route = .editor(DraftSessionModel(draft: draft, storage: storage))
        } catch { self.error = WorkspaceError.normalize(error) }
    }

    func use(_ card: TextCard) async {
        await use(cardID: card.id)
    }

    func use(cardID: UUID) async {
        guard !hasOpenWork else { return }
        opening = true
        defer { opening = false }
        do {
            var current = try await storage.card(id: cardID)
            var draft: WorkDraft?
            if current.usesVariables && !TextTemplate(current.body).names.isEmpty {
                draft = try await storage.preparationDraft(cardID: current.id)
                if let draft, let version = draft.baseVersion {
                    current = TextCard(id: current.id, title: draft.title, body: draft.body,
                                       usesVariables: draft.usesVariables, version: version, modifiedAt: draft.modifiedAt)
                }
            }
            guard route == nil, !Task.isCancelled else { return }
            route = .use(UseSessionModel(card: current, draft: draft, storage: storage))
        } catch { self.error = WorkspaceError.normalize(error) }
    }

    func resume(_ draft: WorkDraft) async {
        guard !hasOpenWork else { return }
        opening = true
        defer { opening = false }
        do {
            let current = try await storage.draft(id: draft.id)
            guard route == nil, !Task.isCancelled else { return }
            switch current.target {
            case .prepare(let id, let version):
                let snapshot = TextCard(id: id, title: current.title, body: current.body,
                                        usesVariables: current.usesVariables, version: version, modifiedAt: current.modifiedAt,
                                        pinned: false, deletedAt: nil, originTitle: nil)
                route = .use(UseSessionModel(card: snapshot, draft: current, storage: storage))
            case .new, .edit:
                route = .editor(DraftSessionModel(draft: current, storage: storage))
            }
        } catch { self.error = WorkspaceError.normalize(error) }
    }

    func pin(_ card: TextCard) async {
        do {
            _ = try await storage.setPinned(!card.pinned, cardID: card.id, expectedVersion: card.version)
            notice = .pinned(!card.pinned)
            await reload()
        } catch { self.error = WorkspaceError.normalize(error) }
    }

    func trash(_ card: TextCard) async {
        do {
            let deleted = try await storage.trash(cardID: card.id, expectedVersion: card.version)
            notice = .trashed(deleted)
            await reload()
        } catch { self.error = WorkspaceError.normalize(error) }
    }

    func restore(_ card: TextCard) async {
        do {
            _ = try await storage.restore(cardID: card.id, expectedVersion: card.version)
            notice = .restored
            await reload()
        } catch { self.error = WorkspaceError.normalize(error) }
    }

    func reload() async {
        await refresh(search: query.query, pinned: query.pinnedOnly, trash: query.trash)
    }

    func finished(saved: Bool = false) async {
        route = nil
        if saved { notice = .saved }
        await reload()
    }
}
