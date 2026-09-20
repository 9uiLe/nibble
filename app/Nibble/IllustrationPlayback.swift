import Foundation
import Observation
import RivePresentation
import RiveRuntime
import SwiftUI

/// One explanation screen owns this state. Loading runs in its SwiftUI task.
@MainActor @Observable
final class IllustrationPlayback {
    private(set) var session: RiveSession?
    private(set) var failed = false
    private var request: UUID?
    private let loadResource: @MainActor (String, Bundle) async throws -> RiveResource

    init(loadResource: @escaping @MainActor (String, Bundle) async throws -> RiveResource = {
        try await RiveResource.load(named: $0, in: $1)
    }) {
        self.loadResource = loadResource
    }

    func load(named name: String, contract: RiveContract) async {
        guard session == nil, !Task.isCancelled else { return }
        let id = UUID()
        request = id
        failed = false
        do {
            // No cross-screen cache: closing the screen releases its file and worker.
            let resource = try await loadResource(name, .main)
            try Task.checkCancellation()
            let loaded = try await resource.makeSession(contract)
            loaded.data.setValue(of: BoolProperty(path: "motionAllowed"), to: true)
            try Task.checkCancellation()
            guard request == id else { return }
            session = loaded
        } catch is CancellationError {
            // A later appearance starts another load; cancelled results stay unpublished.
        } catch {
            guard request == id, !Task.isCancelled else { return }
            failed = true
        }
    }
}

extension EnvironmentValues {
    /// The scene's presentation owner knows when another tab or sheet covers the guide.
    @Entry var illustrationPlaybackAllowed = true
}
