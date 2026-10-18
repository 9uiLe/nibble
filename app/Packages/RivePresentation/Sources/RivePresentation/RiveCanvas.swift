import AppMacros
import SwiftUI

@Equatable
public struct RiveCanvas: View {
    private let inputRevision = UUID()
    @SkipEquatable private let session: RiveSession
    private let paused: Bool
    private let renderingRevision: Int
    @State private var visible = false
    @Environment(\.scenePhase) private var scene

    public init(session: RiveSession, paused: Bool = false, renderingRevision: Int = 0) {
        self.session = session
        self.paused = paused
        self.renderingRevision = renderingRevision
    }

    public var body: some View {
        let canAdvance = visible && scene == .active && !paused
        RiveViewport(session: session, paused: !canAdvance)
            .id(renderingRevision)
            .onAppear { visible = true }
            .onDisappear { visible = false }
    }
}
