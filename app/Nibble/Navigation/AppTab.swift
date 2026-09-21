enum AppTab: String, CaseIterable {
    case library, search, settings

    var title: String {
        switch self {
        case .library: "一覧"
        case .search: "検索"
        case .settings: "設定"
        }
    }

    func symbol(isSelected: Bool) -> String {
        switch self {
        case .library: isSelected ? "house.fill" : "house"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
}
