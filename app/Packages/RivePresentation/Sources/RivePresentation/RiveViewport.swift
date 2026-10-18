import AppMacros
import RiveRuntime
import SwiftUI

@Equatable(.mainActor)
struct RiveViewport: UIViewRepresentable {
    private let inputRevision = UUID()
    @SkipEquatable let session: RiveSession
    let paused: Bool

    func makeUIView(context: Context) -> RiveUIView {
        let surface = RiveUIView(rive: session.rive, isPaused: true)
        synchronize(surface)
        return surface
    }

    func updateUIView(_ uiView: RiveUIView, context: Context) {
        synchronize(uiView)
    }

    private func synchronize(_ surface: RiveUIView) {
        guard surface.rive === session.rive else {
            surface.isPaused = true
            surface.rive = session.rive
            surface.isPaused = paused
            return
        }
        guard surface.isPaused != paused else { return }
        surface.isPaused = paused
    }

    static func dismantleUIView(_ uiView: RiveUIView, coordinator: ()) {
        uiView.isPaused = true
        uiView.rive = nil
    }
}
