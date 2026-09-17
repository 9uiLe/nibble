import RiveRuntime
import SwiftUI

/// The runtime owns the frame clock. The host owns meaning, accessibility and motion preference.
public struct RiveCanvas: View {
    private let session: RiveSession
    private let paused: Bool
    private let renderingRevision: Int
    @Environment(\.scenePhase) private var scenePhase
    @State private var mounted = false

    public init(session: RiveSession, paused: Bool = false, renderingRevision: Int = 0) {
        self.session = session
        self.paused = paused
        self.renderingRevision = renderingRevision
    }

    public var body: some View {
        RiveUIViewRepresentable(rive: session.rive)
            .paused(paused || !mounted || scenePhase != .active)
            // A new viewport draws at delta zero; the session keeps its timeline and bindings.
            .id(renderingRevision)
            .onAppear { mounted = true }
            .onDisappear { mounted = false }
    }
}
