import Foundation

struct AppVersion: Equatable {
    let release: String
    let build: String

    static let current = AppVersion(bundle: .main)

    init(bundle: Bundle) {
        release = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var display: String { "\(release) (\(build))" }
}
