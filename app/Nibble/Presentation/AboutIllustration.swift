import AppMacros
import RivePresentation
import SwiftUI

@MainActor @Equatable
struct AboutIllustration: View {
    @State private var playback: IllustrationPlayback
    init(playback: IllustrationPlayback = IllustrationPlayback()) { _playback = State(initialValue: playback) }
    static let contract = RiveContract(artboard: "About", stateMachine: "Presentation", viewModel: "AboutStory",
        properties: ["active": .boolean, "motionAllowed": .boolean, "paper": .color, "ink": .color, "accent": .color, "muted": .color])
    var body: some View { StoryIllustration(kind: .about, playback: playback) }
}
