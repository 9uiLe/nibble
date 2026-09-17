import RivePresentation
import RiveRuntime
import SwiftUI

struct AboutIllustration: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var session: RiveSession?
    @State private var visible = true
    @State private var failed = false
    @State private var attempt = 0
    @State private var paletteRevision = 0

    static let contract = RiveContract(
        artboard: "About", stateMachine: "Presentation", viewModel: "AboutStory",
        properties: ["motionAllowed": .boolean, "active": .boolean,
                     "paper": .color, "ink": .color, "accent": .color, "muted": .color]
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let session {
                    RiveCanvas(session: session, paused: !visible, renderingRevision: paletteRevision)
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
                .font(.subheadline.weight(.medium))
                .accessibilityLabel("ほかのアプリの文章を選んでコピーし、nibbleに保存します。元の文章はそのまま残ります")
                .accessibilityIdentifier("about.story.caption")

            if failed {
                Button {
                    attempt += 1
                } label: {
                    Label("説明アニメーションを再読み込み", systemImage: "arrow.clockwise")
                        .frame(minHeight: 34)
                }
                .accessibilityIdentifier("about.story.retry")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .task(id: attempt) { await load() }
        .onChange(of: colorScheme) { updatePalette() }
    }

    @MainActor
    private func load() async {
        failed = false
        do {
            if session == nil {
                let resource = try await RiveResource.load(named: "about-story", in: .main)
                let loaded = try await resource.makeSession(Self.contract)
                loaded.data.setValue(of: BoolProperty(path: "motionAllowed"), to: true)
                try Task.checkCancellation()
                session = loaded
                updatePalette()
            }
        } catch is CancellationError {
            // The view owns the session; cancelled loads never replace it.
        } catch {
            guard !Task.isCancelled else { return }
            session = nil
            failed = true
        }
    }

    @MainActor
    private func updatePalette() {
        guard let data = session?.data else { return }
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
    }
}
