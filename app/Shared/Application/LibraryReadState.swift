import Foundation

/// Owns the requested content, complete database snapshots and read admission.
/// Browsing and searching share one owner, but search never replaces a retained collection.
@MainActor
struct LibraryReadState {
    struct Snapshot {
        let request: LibraryRequest
        let page: LibraryPage
    }
    enum Outcome { case loaded, cancelled, failed(any Error) }
    struct Read {
        let id = UUID()
        let requested: LibraryRequest
        let requests: [LibraryRequest]
    }

    let surface: LibrarySurface
    private(set) var selection: LibraryFilter
    private(set) var query = ""
    private var limits: [LibraryFilter: Int] = [:]
    private var searchLimit = LibraryRequest.pageSize
    private var collections: [LibraryFilter: Snapshot] = [:]
    private var searchSnapshot: Snapshot?
    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var usesSearchSnapshot: Bool { surface != .library || isSearching }
    var request: LibraryRequest {
        LibraryRequest(query: isSearching ? query : "",
                       filter: surface == .deleted ? .trash : isSearching ? .all : selection,
                       limit: usesSearchSnapshot ? searchLimit : limits[selection] ?? LibraryRequest.pageSize)
    }
    var snapshot: Snapshot? { usesSearchSnapshot ? searchSnapshot ?? collections[selection] : collections[selection] }
    private var completion: (request: LibraryRequest, outcome: Outcome)?
    private var active: UUID?
    private var collectionRead: UUID?

    init(surface: LibrarySurface) {
        self.surface = surface
        selection = surface == .deleted ? .trash : .all
    }

    var contentRequest: LibraryRequest { snapshot?.request ?? request }
    var contentIsCurrent: Bool {
        snapshot?.request.filter == request.filter && snapshot?.request.query == request.query
    }
    var loading: Bool { active != nil || completion?.request != request }
    var interrupted: Bool {
        guard !loading, completion?.request == request, case .cancelled = completion?.outcome else { return false }
        return true
    }
    var error: (any Error)? {
        guard completion?.request == request, case .failed(let error) = completion?.outcome else { return nil }
        return error
    }
    var demand: LibraryRequest? { completion?.request == request ? nil : request }
    var refreshOnAppearance: Bool { usesSearchSnapshot || snapshot == nil }

    mutating func select(_ filter: LibraryFilter) {
        guard surface == .library, LibrarySurface.collections.contains(filter), filter != selection || isSearching else { return }
        selection = filter
        query = ""
        if let retained = collections[filter], retained.request == request {
            completion = (request, .loaded)
        }
    }

    mutating func showAll() {
        guard surface == .library else { return }
        select(.all)
        // Whitespace is not an active search, but an explicit route still clears the field.
        if !query.isEmpty { search("") }
    }

    mutating func search(_ query: String) {
        guard !SnippetText.hasSameBytes(query, self.query) else { return }
        let previous = request
        self.query = query
        guard !SnippetText.hasSameBytes(previous.query, request.query) else { return }
        searchLimit = LibraryRequest.pageSize
        active = nil
        if !usesSearchSnapshot, let retained = collections[selection], retained.request == request {
            completion = (request, .loaded)
        }
    }

    mutating func showMore() {
        if usesSearchSnapshot { searchLimit = request.expanded.limit }
        else { limits[selection] = request.expanded.limit }
    }

    mutating func begin(includingCollections: Bool = false) -> Read {
        var requests: [LibraryRequest] = []
        if surface == .library && (!isSearching || includingCollections) {
            requests = LibrarySurface.collections.map { filter in
                LibraryRequest(filter: filter, limit: limits[filter] ?? LibraryRequest.pageSize)
            }
        }
        if usesSearchSnapshot { requests.append(request) }
        let read = Read(requested: request, requests: requests)
        active = read.id
        if surface == .library && (!isSearching || includingCollections) { collectionRead = read.id }
        return read
    }

    mutating func end(_ read: Read) {
        if active == read.id { active = nil }
        if collectionRead == read.id { collectionRead = nil }
    }

    private func admits(_ read: Read) -> Bool {
        guard active == read.id else { return false }
        if surface == .library {
            // A selection can change while the same three-collection read is pending.
            return read.requests.contains(request)
        }
        return request == read.requested
    }

    mutating func accept(_ pages: [LibraryPage], from read: Read) throws -> Bool {
        let publishesCurrent = admits(read)
        let retainsCollections = collectionRead == read.id
        guard publishesCurrent || retainsCollections else { return false }
        guard pages.count == read.requests.count else { throw StoreError.unavailable }
        let snapshots = zip(read.requests, pages).map { Snapshot(request: $0, page: $1) }
        for snapshot in snapshots {
            if surface == .library && snapshot.request.query.isEmpty {
                if retainsCollections { collections[snapshot.request.filter] = snapshot }
            } else if publishesCurrent {
                searchSnapshot = snapshot
            }
        }
        // A completed mutation must still refresh browsing after the user clears search.
        // Only the latest collection read can replace that cache; obsolete queries never publish.
        if publishesCurrent || (retainsCollections && !usesSearchSnapshot && snapshot?.request == request) {
            completion = (request, .loaded)
        }
        return true
    }

    mutating func complete(_ outcome: Outcome, from read: Read) {
        if admits(read) { completion = (request, outcome) }
    }
}
