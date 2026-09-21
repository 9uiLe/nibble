import AppMacros
import RivePresentation
import RiveRuntime
import SwiftUI

@Equatable
struct KeyboardIllustration: View {
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
        artboard: "Keyboard", stateMachine: "Presentation", viewModel: "KeyboardStory",
        properties: ["motionAllowed": .boolean, "active": .boolean,
                     "paper": .color, "ink": .color, "accent": .color,
                     "muted": .color, "action": .color]
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let session = playback.session, appliedColorScheme != nil {
                    RiveCanvas(session: session, paused: !visible || !playbackAllowed, renderingRevision: paletteRevision)
                        .allowsHitTesting(false)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "text.cursor")
                        Image(systemName: "arrow.up").font(.body)
                        Image(systemName: "keyboard")
                    }
                    .font(.largeTitle).foregroundStyle(Color.nibbleAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .aspectRatio(360.0 / 320.0, contentMode: .fit)
            .accessibilityHidden(true)
            .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }

            Text("切り替える → 項目をタップ → 本文を入力")
                .font(.nibbleBody)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("入力先でnibbleキーボードに切り替え、項目をタップすると、保存した本文を挿入できます。保存した文章はそのまま残ります。入力先に反映されたか確認してください")
                .accessibilityIdentifier("keyboard.story.caption")

            Text("保存した文章はそのまま残ります。")
                .font(.nibbleBody)
                .accessibilityHidden(true)

            if playback.failed {
                Button {
                    attempt += 1
                } label: {
                    Label("説明アニメーションを再読み込み", systemImage: "arrow.clockwise")
                        .font(.nibbleTitle)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("keyboard.story.retry")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .task(id: attempt) {
            await playback.load(named: "keyboard-story", contract: Self.contract)
        }
        // Use the current appearance, including changes while loading or offscreen.
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
            ("muted", dark ? 0xFF727980 : 0xFFBFC5CB),
            ("action", dark ? 0xFF72B5FF : 0xFF2878CB)
        ]
        for (name, argb) in colors {
            data.setValue(of: ColorProperty(path: name), to: RiveRuntime.Color(argb))
        }
        // Refresh a paused viewport without resetting the session's timeline.
        paletteRevision += 1
        appliedColorScheme = colorScheme
    }
}
