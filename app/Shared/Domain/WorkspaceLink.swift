import Foundation

enum WorkspaceLink: Equatable, Sendable {
    case library
    case create(title: String, body: String)
    case use(UUID)

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "nibble",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { return nil }
        let items = parts.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count,
              items.allSatisfy({ ($0.value?.utf8.count ?? 0) <= 1_048_576 }) else { return nil }
        switch parts.host {
        case "library":
            guard items.isEmpty else { return nil }
            self = .library
        case "create":
            guard items.allSatisfy({ ["title", "text"].contains($0.name) }) else { return nil }
            self = .create(title: items.first(where: { $0.name == "title" })?.value ?? "",
                           body: items.first(where: { $0.name == "text" })?.value ?? "")
        case "use":
            guard items.count == 1, items[0].name == "id", let raw = items[0].value, let id = UUID(uuidString: raw) else { return nil }
            self = .use(id)
        default: return nil
        }
    }
}
