import AppMacros
import RiveRuntime
import SwiftUI

/// The runtime owns the frame clock. The host owns meaning, accessibility and motion preference.
@Equatable
public struct RiveCanvas: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    @SkipEquatable private let session: RiveSession
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
        RiveViewport(session: session, paused: paused || !mounted || scenePhase != .active)
            // A new viewport draws at delta zero; the session keeps its timeline and bindings.
            .id(renderingRevision)
            .onAppear { mounted = true }
            .onDisappear { mounted = false }
    }
}

/// Dismantling is a synchronous lifetime boundary, even if SwiftUI no longer
/// delivers the state update made by onDisappear to the departing representable.
@Equatable(.mainActor)
private struct RiveViewport: UIViewRepresentable {
    private let inputRevision = UUID()
    @SkipEquatable let session: RiveSession
    let paused: Bool

    init(session: RiveSession, paused: Bool) {
        self.session = session
        self.paused = paused
    }

    func makeUIView(context: Context) -> RiveUIView {
        RiveUIView(rive: session.rive, isPaused: paused)
    }

    func updateUIView(_ view: RiveUIView, context: Context) {
        if view.rive !== session.rive { view.rive = session.rive }
        if view.isPaused != paused { view.isPaused = paused }
    }

    static func dismantleUIView(_ view: RiveUIView, coordinator: ()) {
        view.isPaused = true
        view.rive = nil
    }
}
