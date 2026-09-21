import AppMacros
import RiveRuntime
import SwiftUI

/// Dismantling is a synchronous lifetime boundary, even if SwiftUI no longer
/// delivers the state update made by onDisappear to the departing representable.
@Equatable(.mainActor)
struct RiveViewport: UIViewRepresentable {
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
