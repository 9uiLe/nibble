import Foundation

/// Owns the requested content, complete database snapshots and read admission.
/// Selection among the library's three collections never creates a read demand.
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
    private(set) var request: LibraryRequest
    private(set) var snapshot: Snapshot?
    private var collections: [LibraryFilter: Snapshot] = [:]
    private var completion: (request: LibraryRequest, outcome: Outcome)?
    private var active: UUID?

    init(surface: LibrarySurface) {
        self.surface = surface
        request = LibraryRequest(filter: surface == .deleted ? .trash : .all)
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
    var refreshOnAppearance: Bool { surface != .library || snapshot == nil }

    mutating func select(_ filter: LibraryFilter) {
        guard surface == .library, filter != .trash, filter != request.filter else { return }
        if let retained = collections[filter] {
            request = retained.request
            snapshot = retained
            completion = (request, .loaded)
        } else {
            request = LibraryRequest(filter: filter)
        }
    }

    mutating func search(_ query: String) {
        guard surface != .library, !SnippetText.hasSameBytes(query, request.query) else { return }
        request = LibraryRequest(query: query, filter: request.filter)
    }

    mutating func showMore() { request = request.expanded }

    mutating func begin() -> Read {
        let requests = surface == .library ? [LibraryFilter.all, .pinned, .drafts].map { filter in
            LibraryRequest(filter: filter, limit: filter == request.filter ? request.limit
                : collections[filter]?.request.limit ?? LibraryRequest.pageSize)
        } : [request]
        let read = Read(requested: request, requests: requests)
        active = read.id
        return read
    }

    mutating func end(_ read: Read) {
        if active == read.id { active = nil }
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
        guard admits(read) else { return false }
        guard pages.count == read.requests.count else { throw StoreError.unavailable }
        let snapshots = zip(read.requests, pages).map { Snapshot(request: $0, page: $1) }
        if surface == .library {
            collections = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.request.filter, $0) })
        }
        snapshot = snapshots.first { $0.request == request }
        completion = (request, .loaded)
        return true
    }

    mutating func complete(_ outcome: Outcome, from read: Read) {
        if admits(read) { completion = (request, outcome) }
    }
}
