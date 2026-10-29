import AppMacros
import SwiftUI
import Tasking

@MainActor @Equatable
struct PromptEditorView: View {
    private enum Action { case cancel, discard, save, checkpoint }
    private let inputRevision = UUID()
    @SkipEquatable let model: DraftSessionModel
    let onFinished: @MainActor (Bool) async -> Void
    @State private var tasks = ViewTaskStore()
    @State private var confirmDiscard = false
    @State private var shownFailure: WorkspaceError?
    @Environment(\.scenePhase) private var phase

    private var creating: Bool {
        if case .new = model.draft.target { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Button { startTask(.cancel) } label: { PromptIconLabel(title: "キャンセル", symbol: "xmark") }
                    .buttonStyle(.plain).accessibilityIdentifier("workspace.editor.close")
                    .disabled(model.busy || model.isComposing)
                Spacer()
                Button { startTask(.save) } label: { PromptIconLabel(title: creating ? "プロンプトを保存" : "本文を保存", symbol: "checkmark") }
                    .buttonStyle(.plain).accessibilityIdentifier("workspace.editor.save")
                    .disabled(!model.canSavePrompt)
                    .opacity(model.canSavePrompt ? 1 : 0.42)
            }
            Group {
                if creating {
                    ZStack(alignment: .leading) {
                        if model.draft.title.isEmpty {
                            Text("タイトル").foregroundStyle(WorkspaceStyle.secondary).allowsHitTesting(false)
                        }
                        NativeDocumentField(text: Binding(get: { model.draft.title }, set: { model.update(title: $0) }),
                                            composing: Binding(get: { model.isComposing }, set: { model.isComposing = $0 }),
                                            identifier: "workspace.editor.title", label: "タイトル", singleLine: true, appearance: .promptTitle)
                    }
                } else {
                    Text(verbatim: WorkspacePresentation.title(model.draft.title, body: model.draft.body))
                        .accessibilityIdentifier("workspace.editor.title.readonly")
                }
            }
            .font(.title3.weight(.semibold))
            .frame(minHeight: 44, alignment: creating ? .leading : .topLeading)
            VStack(alignment: .leading, spacing: 8) {
                Text("本文").font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
                    .frame(minHeight: 27, alignment: .topLeading)
                ZStack(alignment: .topLeading) {
                    if model.draft.body.isEmpty {
                        Text("繰り返し使う指示を入力")
                            .foregroundStyle(WorkspaceStyle.secondary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                    NativeDocumentField(text: Binding(get: { model.draft.body }, set: { model.update(body: $0) }),
                                        composing: Binding(get: { model.isComposing }, set: { model.isComposing = $0 }),
                                        identifier: "workspace.editor.body", label: "本文", appearance: .promptBody)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.isComposing {
                    Text("文字の変換を確定してから保存してください。")
                        .font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
                }
            }
        }
        .disabled(model.busy)
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .foregroundStyle(WorkspaceStyle.text)
        .background(Color(uiColor: .systemBackground))
        .tint(.primary)
        .interactiveDismissDisabled()
        .alert("変更を破棄しますか？", isPresented: $confirmDiscard) {
            Button("編集を続ける", role: .cancel) {}
            Button("変更を破棄", role: .destructive) { startTask(.discard) }
        } message: { Text("保存していない変更は失われます。") }
        .alert("保存できませんでした", isPresented: Binding(get: { shownFailure != nil }, set: { if !$0 { shownFailure = nil } }), presenting: shownFailure) { _ in
            Button("入力に戻る", role: .cancel) {}
        } message: { error in Text(PromptPresentation.error(error)) }
        .task(id: model.draft.sequence) { await model.checkpoint() }
        .onChange(of: model.error) { _, error in
            if !model.isComposing { shownFailure = error }
        }
        .onChange(of: model.isComposing) { _, composing in
            if !composing { shownFailure = model.error }
        }
        .onChange(of: phase) { _, phase in
            if phase != .active { startTask(.checkpoint) }
        }
        .onDisappear { tasks.cancel(lifetime: .screenBound) }
    }

    private func startTask(_ action: Action) {
        tasks.start(id: "prompt.editor.action", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            switch action {
            case .checkpoint: await model.checkpoint()
            case .cancel:
                if model.hasChanges { confirmDiscard = true; return }
                guard await model.discard() else { shownFailure = model.error; return }
                await onFinished(false)
            case .discard:
                guard await model.discard() else { shownFailure = model.error; return }
                await onFinished(false)
            case .save:
                guard await model.save() != nil else { shownFailure = model.error; return }
                await onFinished(true)
            }
        }
    }
}
