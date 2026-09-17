import RivePresentation
import RiveRuntime
import SwiftUI

struct AboutIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var session: RiveSession?
    @State private var active = false
    @State private var paused = false
    @State private var visible = true
    @State private var failed = false
    @State private var attempt = 0
    @State private var paletteRevision = 0

    static let contract = RiveContract(
        artboard: "About", stateMachine: "Presentation", viewModel: "AboutStory",
        properties: ["motionAllowed": .boolean, "replay": .trigger, "active": .boolean,
                     "paper": .color, "ink": .color, "accent": .color, "muted": .color]
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let session {
                    RiveCanvas(session: session, paused: paused || !visible, renderingRevision: paletteRevision)
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
            .aspectRatio(400.0 / 208.0, contentMode: .fit)
            .accessibilityHidden(true)
            .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }

            Text("選ぶ → コピー → ペースト")
                .font(.subheadline.weight(.medium))
                .accessibilityLabel("保存した言葉を選び、コピーして、使いたいアプリにペーストします")
                .accessibilityIdentifier("about.story.caption")

            if failed {
                Button {
                    attempt += 1
                } label: {
                    Label("説明アニメーションを再読み込み", systemImage: "arrow.clockwise")
                        .frame(minHeight: 34)
                }
                .accessibilityIdentifier("about.story.retry")
            } else if !reduceMotion, let session {
                Button {
                    if active {
                        paused.toggle()
                    } else {
                        paused = false
                        session.data.fire(trigger: TriggerProperty(path: "replay"))
                    }
                } label: {
                    Label(buttonTitle, systemImage: buttonSymbol).frame(minHeight: 34)
                }
                .accessibilityIdentifier("about.story.playback")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .task(id: attempt) { await loadAndObserve() }
        .onChange(of: colorScheme) { updatePalette() }
        .onChange(of: contrast) { updatePalette() }
        .onChange(of: reduceMotion) {
            paused = false
            session?.data.setValue(of: BoolProperty(path: "motionAllowed"), to: !reduceMotion)
        }
    }

    private var buttonTitle: String { active ? (paused ? "再生" : "一時停止") : "もう一度見る" }
    private var buttonSymbol: String { active ? (paused ? "play.fill" : "pause.fill") : "arrow.counterclockwise" }

    @MainActor
    private func loadAndObserve() async {
        failed = false
        do {
            if session == nil {
                let resource = try await RiveResource.load(named: "about-story", in: .main)
                let loaded = try await resource.makeSession(Self.contract)
                loaded.data.setValue(of: BoolProperty(path: "motionAllowed"), to: !reduceMotion)
                try Task.checkCancellation()
                session = loaded
                updatePalette()
            }
            guard let session else { return }
            for try await value in session.data.valueStream(of: BoolProperty(path: "active")) {
                try Task.checkCancellation()
                active = value
            }
        } catch is CancellationError {
            // Leaving the screen cancels loading/subscription; existing playback stays owned by this view.
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
        let strong = contrast == .increased
        let colors: [(String, UInt32)] = [
            ("paper", dark ? 0xFF252822 : 0xFFFFFDF8),
            ("ink", dark ? 0xFFF1E9E0 : 0xFF514238),
            ("accent", dark ? 0xFFFFA366 : 0xFFA33D14),
            ("muted", dark ? (strong ? 0xFF8D897C : 0xFF555348) : (strong ? 0xFF8D7965 : 0xFFE2D4C3))
        ]
        for (name, argb) in colors {
            data.setValue(of: ColorProperty(path: name), to: RiveRuntime.Color(argb))
        }
        // Rive 6.27 does not draw binding changes while manually paused.
        paletteRevision += 1
    }
}
