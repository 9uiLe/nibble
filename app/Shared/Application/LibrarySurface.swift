enum LibrarySurface {
    case library
    case deleted

    static let collections: [LibraryFilter] = [.all, .pinned, .drafts]

    var noticeOrigin: LibraryModel.Notice.Origin {
        switch self {
        case .deleted: .trash
        case .library: .library
        }
    }
}
