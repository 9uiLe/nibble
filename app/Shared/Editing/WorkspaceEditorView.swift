import AppMacros
import SwiftUI
import Tasking

@MainActor @Equatable
struct WorkspaceEditorView: View {
    private enum Action { case close, save, discard, saveAsNew, checkpoint }
    private let inputRevision = UUID()
    @SkipEquatable let model: DraftSessionModel
    let onFinished: @MainActor (Bool) async -> Void
    @State private var tasks = ViewTaskStore()
    @State private var confirmDiscard = false
    @State private var shownFailure: WorkspaceError?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("保存するまで、利用する文章は変わりません。閉じると作業中に残ります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("名前（任意）") {
                    NativeDocumentField(text: Binding(get: { model.draft.title }, set: { model.update(title: $0) }),
                                        composing: Binding(get: { model.isComposing }, set: { model.isComposing = $0 }),
                                        identifier: "workspace.editor.title", label: "文章の名前", singleLine: true)
                        .frame(minHeight: 48)
                }
                Section("本文") {
                    NativeDocumentField(text: Binding(get: { model.draft.body }, set: { model.update(body: $0) }),
                                        composing: Binding(get: { model.isComposing }, set: { model.isComposing = $0 }),
                                        identifier: "workspace.editor.body", label: "文章の本文")
                        .frame(minHeight: 200, idealHeight: 260, maxHeight: 320)
                }
                Section {
                    Toggle("差し替えを使う", isOn: Binding(get: { model.draft.usesVariables }, set: { model.update(usesVariables: $0) }))
                        .accessibilityIdentifier("workspace.editor.variables")
                    Text(model.draft.usesVariables ? "{{宛名}} のような印を、使うときに差し替えます。ひな型の原文は残ります。" : "本文を文字どおりに使います。{{ }} を含むコードや文章も、そのまま保存できます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.isComposing {
                    Text("文字の変換を確定してから保存してください。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.error {
                    Section { WorkspaceErrorView(error: error) }
                }
                if WorkspacePresentation.canRecoverIndependently(model.error) || model.hasIndependentRecovery {
                    Section {
                        Button("別の文章として保存し、元の作業も残す") { startTask(.saveAsNew) }
                            .accessibilityIdentifier("workspace.editor.saveAsNew")
                        if model.hasIndependentRecovery {
                            Text("独立保存のための作業も残しています。中断後は「作業中」の「作成中」から本文を確認して再開できます。元の作業も残ります。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Text(model.hasCheckpoint ? "作業中の内容を保持しました" : "作業中の内容を保持しています…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("workspace.editor.checkpoint")
                    if model.discardsLocalInputOnly {
                        Text("別の画面の作業は変更せず、この画面の入力だけを破棄して閉じられます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(model.discardsLocalInputOnly ? "この画面の入力を破棄して閉じる" : "作業を破棄", role: .destructive) { confirmDiscard = true }
                        .accessibilityIdentifier("workspace.editor.discard")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(model.busy)
            .navigationTitle("文章を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { startTask(.close) }
                        .disabled(model.busy || model.isComposing)
                        .accessibilityIdentifier("workspace.editor.close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { startTask(.save) }
                        .disabled(model.busy || model.isComposing)
                        .accessibilityIdentifier("workspace.editor.save")
                }
            }
            .confirmationDialog(model.discardsLocalInputOnly ? "この画面の入力だけを破棄しますか？ 別の画面の作業と保存済みの文章は変更しません。" : "この作業中の入力を破棄しますか？ 保存済みの文章は変わりません。", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button(model.discardsLocalInputOnly ? "この画面の入力だけを破棄して閉じる" : "作業中の入力を破棄", role: .destructive) { startTask(.discard) }
            }
        }
        .interactiveDismissDisabled()
        .alert("操作を完了できませんでした", isPresented: Binding(get: { shownFailure != nil }, set: { if !$0 { shownFailure = nil } }), presenting: shownFailure) { _ in
            Button("入力に戻る", role: .cancel) {}
        } message: { error in
                Text(WorkspacePresentation.error(error))
                .accessibilityIdentifier("workspace.failure.message")
        }
        .onChange(of: model.error) { _, _ in presentFailure() }
        .onChange(of: model.isComposing) { _, composing in
            if !composing { presentFailure() }
        }
        .task(id: model.draft.sequence) { await model.checkpoint() }
        .onChange(of: phase) { _, phase in
            if phase != .active { startTask(.checkpoint) }
        }
        .onDisappear { tasks.cancel(lifetime: .screenBound) }
    }

    private func presentFailure() {
        guard !model.isComposing, let error = model.error else { return }
        shownFailure = error
    }

    private func startTask(_ action: Action) {
        tasks.start(id: "workspace.editor.action", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            switch action {
            case .checkpoint:
                await model.checkpoint()
                presentFailure()
            case .close:
                guard await model.suspend() else { presentFailure(); return }
                try cancellation.check()
                await onFinished(false)
            case .save:
                guard await model.save() != nil else { presentFailure(); return }
                await onFinished(true)
            case .discard:
                guard await model.discard() else { presentFailure(); return }
                await onFinished(false)
            case .saveAsNew:
                guard await model.saveAsNew() != nil else { presentFailure(); return }
                await onFinished(true)
            }
        }
    }
}
