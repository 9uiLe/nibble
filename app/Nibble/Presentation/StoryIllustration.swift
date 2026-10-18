import AppMacros
import RivePresentation
import RiveRuntime
import SwiftUI

@MainActor @Equatable
struct StoryIllustration: View {
    enum Kind: Equatable { case about, keyboard }
    private let inputRevision = UUID()
    let kind: Kind
    @SkipEquatable let playback: IllustrationPlayback
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var appearance
    @Environment(\.illustrationPlaybackAllowed) private var allowed
    @State private var visible = false
    @State private var attempt = 0
    @State private var palette = 0
    @State private var appliedAppearance: ColorScheme?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let session = playback.session, appliedAppearance != nil {
                    RiveCanvas(session: session, paused: !visible || !allowed || phase != .active, renderingRevision: palette)
                } else {
                    Image(systemName: kind == .about ? "document.on.clipboard" : "keyboard")
                        .font(.largeTitle).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .aspectRatio(kind == .about ? 1.6 : 1.125, contentMode: .fit)
            .allowsHitTesting(false).accessibilityHidden(true)
            .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
            Text(kind == .about ? "選ぶ → コピー → nibbleに保存" : "切り替える → 項目をタップ → 本文を入力")
                .font(.nibbleBody).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(kind == .about ? "ほかのアプリの文章を選んでコピーし、nibbleに保存します。元の文章はそのまま残ります" : "入力先でnibbleキーボードに切り替え、項目をタップすると、保存した本文を挿入できます。保存した文章はそのまま残ります。入力先に反映されたか確認してください")
                .accessibilityIdentifier(kind == .about ? "about.story.caption" : "keyboard.story.caption")
            if kind == .keyboard { Text("保存した文章はそのまま残ります。").font(.nibbleBody) }
            if playback.failed {
                Text("説明の図を読み込めませんでした。使い方は前後の文章でも確認できます。").font(.nibbleBody)
                Button { attempt += 1 } label: {
                    Label("説明アニメーションを再読み込み", systemImage: "arrow.clockwise")
                        .font(.nibbleTitle).frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }.accessibilityIdentifier(kind == .about ? "about.story.retry" : "keyboard.story.retry")
            }
        }
        .task(id: attempt) {
            await playback.load(named: kind == .about ? "about-story" : "keyboard-story", contract: kind == .about ? AboutIllustration.contract : KeyboardIllustration.contract)
        }
        .onChange(of: playback.session != nil, initial: true) { applyPalette() }
        .onChange(of: appearance) { applyPalette() }
        .onDisappear { visible = false }
    }
    private func applyPalette() {
        guard let data = playback.session?.data, appliedAppearance != appearance else { return }
        let night = appearance == .dark
        let entries: [(String, UInt32)] = [
            ("paper", night ? 0xff25282c : 0xfffffdfc), ("ink", night ? 0xfff1f1ef : 0xff31373d),
            ("accent", night ? 0xffffa366 : 0xffd66c39), ("muted", night ? 0xff727980 : 0xffbfc5cb)
        ]
        for (name, color) in entries { data.setValue(of: ColorProperty(path: name), to: RiveRuntime.Color(color)) }
        if kind == .keyboard { data.setValue(of: ColorProperty(path: "action"), to: RiveRuntime.Color(night ? 0xff72b5ff : 0xff2878cb)) }
        appliedAppearance = appearance
        palette += 1
    }
}
