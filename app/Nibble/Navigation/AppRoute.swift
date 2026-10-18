import Foundation

enum AppRoute: Equatable {
    case library, create
    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "nibble", parts.path.isEmpty, parts.query == nil,
              parts.fragment == nil, parts.port == nil, parts.user == nil, parts.password == nil else { return nil }
        switch parts.host {
        case "library": self = .library
        case "new": self = .create
        default: return nil
        }
    }
}
