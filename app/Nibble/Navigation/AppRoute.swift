import Foundation

enum AppRoute: Equatable {
    case library, create

    init?(url: URL) {
        guard url.scheme == "nibble", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil, url.path.isEmpty else { return nil }
        switch url.host {
        case "library": self = .library
        case "new": self = .create
        default: return nil
        }
    }
}
