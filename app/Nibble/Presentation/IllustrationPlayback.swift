import Foundation
import Observation
import RivePresentation
import RiveRuntime
import SwiftUI

@MainActor @Observable
final class IllustrationPlayback {
    private(set) var session: RiveSession?
    private(set) var failed = false
    private var loading: UUID?
    private let loadResource: @MainActor (String, Bundle) async throws -> RiveResource
    init(loadResource: @escaping @MainActor (String, Bundle) async throws -> RiveResource = { try await RiveResource.load(named: $0, in: $1) }) {
        self.loadResource = loadResource
    }
    func load(named name: String, contract: RiveContract) async {
        guard session == nil, !Task.isCancelled else { return }
        let request = UUID()
        loading = request
        failed = false
        do {
            let file = try await loadResource(name, .main)
            try Task.checkCancellation()
            let prepared = try await file.makeSession(contract)
            try Task.checkCancellation()
            guard loading == request else { return }
            prepared.data.setValue(of: BoolProperty(path: "motionAllowed"), to: true)
            session = prepared
        } catch is CancellationError { }
        catch { if loading == request && !Task.isCancelled { failed = true } }
    }
}
extension EnvironmentValues { @Entry var illustrationPlaybackAllowed = true }
