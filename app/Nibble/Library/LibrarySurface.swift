/// A library surface fixes its navigation and search controls independently of its data filter.
enum LibrarySurface {
    case library, search, deleted

    var title: String {
        switch self {
        case .library: "一覧"
        case .search: "検索"
        case .deleted: "削除した項目"
        }
    }

    var showsFilters: Bool { self == .library }
    var showsSearchPrompt: Bool { self == .search }
    var isRoot: Bool { self != .deleted }
}
