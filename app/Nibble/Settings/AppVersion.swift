import Foundation

struct AppVersion: Equatable {
    let release: String
    let build: String
    static let current = AppVersion(bundle: .main)
    init(bundle: Bundle) {
        let info = bundle.infoDictionary ?? [:]
        release = info["CFBundleShortVersionString"] as? String ?? "—"
        build = info["CFBundleVersion"] as? String ?? "—"
    }
    var display: String { release + " (" + build + ")" }
}
