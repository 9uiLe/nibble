import Foundation

@MainActor
struct LibraryReadState {
    struct Snapshot {
        let request: LibraryRequest
        let page: LibraryPage
    }

    enum Outcome {
        case loaded
        case cancelled
        case failed(any Error)
    }

    struct Read {
        let id: UUID
        let requested: LibraryRequest
        let requests: [LibraryRequest]
    }

    let surface: LibrarySurface
    private(set) var selection: LibraryFilter
    private(set) var query = ""
    private var retained: [LibraryFilter: Snapshot] = [:]
    private var searched: Snapshot?
    private var pageLimits: [LibraryFilter: Int] = [:]
    private var searchLimit = LibraryRequest.pageSize
    private var displayedRead: UUID?
    private var retainedRead: UUID?
    private var settled: (LibraryRequest, Outcome)?

    init(surface: LibrarySurface) {
        self.surface = surface
        selection = surface == .deleted ? .trash : .all
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var presentsSearch: Bool { isSearching || surface == .deleted }

    var request: LibraryRequest {
        let filter: LibraryFilter = surface == .deleted ? .trash : isSearching ? .all : selection
        let limit = presentsSearch ? searchLimit : pageLimits[selection, default: LibraryRequest.pageSize]
        return LibraryRequest(query: isSearching ? query : "", filter: filter, limit: limit)
    }

    var snapshot: Snapshot? {
        guard presentsSearch else { return retained[selection] }
        return searched ?? retained[selection]
    }

    var contentRequest: LibraryRequest { snapshot?.request ?? request }
    var contentIsCurrent: Bool {
        guard let shown = snapshot?.request else { return false }
        return shown.filter == request.filter && SnippetText.hasSameBytes(shown.query, request.query)
    }

    var loading: Bool { displayedRead != nil || settled?.0 != request }
    var demand: LibraryRequest? { settled?.0 == request ? nil : request }
    var refreshOnAppearance: Bool { displayedRead == nil && (presentsSearch || snapshot == nil) }
    var interrupted: Bool {
        guard !loading, settled?.0 == request, case .cancelled = settled?.1 else { return false }
        return true
    }

    var error: (any Error)? {
        guard settled?.0 == request, case .failed(let error) = settled?.1 else { return nil }
        return error
    }

    mutating func select(_ filter: LibraryFilter) {
        guard surface == .library, LibrarySurface.collections.contains(filter) else { return }
        selection = filter
        query = ""
        settleRetainedPage()
    }

    mutating func showAll() {
        guard surface == .library else { return }
        select(.all)
    }

    mutating func search(_ value: String) {
        guard !SnippetText.hasSameBytes(value, query) else { return }
        let former = request
        query = value
        guard !SnippetText.hasSameBytes(former.query, request.query) else { return }
        searchLimit = LibraryRequest.pageSize
        displayedRead = nil
        settleRetainedPage()
    }

    mutating func showMore() {
        let next = request.expanded.limit
        if presentsSearch { searchLimit = next }
        if !presentsSearch { pageLimits[selection] = next }
    }

    mutating func begin(includingCollections: Bool = false) -> Read {
        let readsCollections = surface == .library && (includingCollections || !isSearching)
        var batch = readsCollections ? LibrarySurface.collections.map {
            LibraryRequest(filter: $0, limit: pageLimits[$0, default: LibraryRequest.pageSize])
        } : []
        if presentsSearch { batch.append(request) }
        let work = Read(id: UUID(), requested: request, requests: batch)
        displayedRead = work.id
        if readsCollections { retainedRead = work.id }
        return work
    }

    mutating func end(_ work: Read) {
        if displayedRead == work.id { displayedRead = nil }
        if retainedRead == work.id { retainedRead = nil }
    }

    mutating func accept(_ pages: [LibraryPage], from work: Read) throws -> Bool {
        let showsResult = canDisplay(work)
        let keepsResult = retainedRead == work.id
        guard showsResult || keepsResult else { return false }
        guard pages.count == work.requests.count else { throw StoreError.unavailable }
        for (requested, page) in zip(work.requests, pages) {
            let value = Snapshot(request: requested, page: page)
            switch (surface, requested.query.isEmpty) {
            case (.library, true):
                if keepsResult { retained[requested.filter] = value }
            default:
                if showsResult { searched = value }
            }
        }
        if showsResult { settled = (request, .loaded) }
        if keepsResult, !presentsSearch { settleRetainedPage() }
        return true
    }

    mutating func complete(_ outcome: Outcome, from work: Read) {
        guard canDisplay(work) else { return }
        settled = (request, outcome)
    }

    private func canDisplay(_ work: Read) -> Bool {
        guard displayedRead == work.id else { return false }
        return work.requests.contains(request)
    }

    private mutating func settleRetainedPage() {
        guard !presentsSearch, retained[selection]?.request == request else { return }
        settled = (request, .loaded)
    }
}
