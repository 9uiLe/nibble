import AppMacros
import RivePresentation
import SwiftUI

@MainActor @Equatable
struct KeyboardIllustration: View {
    @State private var playback: IllustrationPlayback
    init(playback: IllustrationPlayback = IllustrationPlayback()) { _playback = State(initialValue: playback) }
    static let contract = RiveContract(artboard: "Keyboard", stateMachine: "Presentation", viewModel: "KeyboardStory",
        properties: ["active": .boolean, "motionAllowed": .boolean, "paper": .color, "ink": .color, "accent": .color, "muted": .color, "action": .color])
    var body: some View { StoryIllustration(kind: .keyboard, playback: playback) }
}
