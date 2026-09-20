import AppMacros
import RivePresentation
import RiveRuntime
import SwiftUI

@Equatable
struct AboutIllustration: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.illustrationPlaybackAllowed) private var playbackAllowed
    @State private var playback: IllustrationPlayback
    @State private var visible = false
    @State private var attempt = 0
    @State private var paletteRevision = 0
    @State private var appliedColorScheme: ColorScheme?

    init(playback: IllustrationPlayback = IllustrationPlayback()) {
        _playback = State(initialValue: playback)
    }

    static let contract = RiveContract(
        artboard: "About", stateMachine: "Presentation", viewModel: "AboutStory",
        properties: ["motionAllowed": .boolean, "active": .boolean,
                     "paper": .color, "ink": .color, "accent": .color, "muted": .color]
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let session = playback.session, appliedColorScheme != nil {
                    RiveCanvas(session: session, paused: !visible || !playbackAllowed, renderingRevision: paletteRevision)
                        .allowsHitTesting(false)
                } else {
                    HStack(spacing: 24) {
                        Image(systemName: "text.document")
                        Image(systemName: "arrow.right").font(.body)
                        Image(systemName: "document.on.clipboard")
                    }
                    .font(.largeTitle).foregroundStyle(Color.nibbleAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .aspectRatio(480.0 / 300.0, contentMode: .fit)
            .accessibilityHidden(true)
            .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }

            Text("選ぶ → コピー → nibbleに保存")
                .font(.nibbleBody)
                .accessibilityLabel("ほかのアプリの文章を選んでコピーし、nibbleに保存します。元の文章はそのまま残ります")
                .accessibilityIdentifier("about.story.caption")

            if playback.failed {
                Button {
                    attempt += 1
                } label: {
                    Label("説明アニメーションを再読み込み", systemImage: "arrow.clockwise")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("about.story.retry")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .task(id: attempt) {
            await playback.load(named: "about-story", contract: Self.contract)
        }
        // Task closures can retain an earlier appearance across loading or tab returns.
        // Resolve the current palette before mounting the first viewport.
        .onChange(of: playback.session != nil, initial: true) { updatePalette() }
        .onChange(of: colorScheme) { updatePalette() }
    }

    @MainActor
    private func updatePalette() {
        guard let data = playback.session?.data, appliedColorScheme != colorScheme else { return }
        let dark = colorScheme == .dark
        let colors: [(String, UInt32)] = [
            ("paper", dark ? 0xFF25282C : 0xFFFFFDFC),
            ("ink", dark ? 0xFFF1F1EF : 0xFF31373D),
            ("accent", dark ? 0xFFFFA366 : 0xFFD66C39),
            ("muted", dark ? 0xFF727980 : 0xFFBFC5CB)
        ]
        for (name, argb) in colors {
            data.setValue(of: ColorProperty(path: name), to: RiveRuntime.Color(argb))
        }
        // Rive 6.27 needs a viewport refresh for binding changes while offscreen.
        paletteRevision += 1
        appliedColorScheme = colorScheme
    }
}
