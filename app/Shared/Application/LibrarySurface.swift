/// A surface fixes its controls, permitted requests, refresh policy and notice origin.
enum LibrarySurface {
    case library, search, deleted

    static let collections: [LibraryFilter] = [.all, .pinned, .drafts]

    var noticeOrigin: LibraryModel.Notice.Origin {
        switch self {
        case .library: .library
        case .search: .search
        case .deleted: .trash
        }
    }

}
