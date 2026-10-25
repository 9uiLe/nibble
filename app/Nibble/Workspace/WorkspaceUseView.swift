import AppMacros
import SwiftUI
import Tasking

@MainActor @Equatable
struct WorkspaceUseView: View {
    private enum Action { case close, copy, saveCompletion, independent, discard, checkpoint }
    private let inputRevision = UUID()
    @SkipEquatable let model: UseSessionModel
    @SkipEquatable let delivery: any TextDelivery
    let onFinished: @MainActor () async -> Void
    @State private var tasks = ViewTaskStore()
    @State private var confirmDiscard = false
    @State private var shownFailure: WorkspaceError?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: WorkspacePresentation.title(model.card)).font(.headline).lineLimit(3)
                    if let origin = model.card.originTitle {
                        Text("「\(origin)」から作った固定文です。元のひな型が変わっても、この文章は自動で変わりません。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !model.names.isEmpty {
                    Section {
                        Text("ひな型は変えず、今回使う値を入れます。入力途中も作業中に保持します。")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(model.names, id: \.self) { name in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: name).font(.subheadline)
                                NativeDocumentField(text: Binding(get: { model.values[name] ?? "" }, set: { model.updateValue($0, for: name) }),
                                                    composing: Binding(get: { model.isComposing }, set: { model.isComposing = $0 }),
                                                    identifier: "workspace.value.\(name)", label: name)
                                    .frame(minHeight: 56, idealHeight: 72)
                            }
                        }
                    } header: { Text("今回の差し替え") }
                }
                Section {
                    switch model.output {
                    case .some(let body):
                        NativeDocumentPreview(text: body, identifier: "workspace.use.preview")
                            .frame(minHeight: 120, idealHeight: 280, maxHeight: 360)
                    case .none:
                        Text("差し替える値が揃うと、ここに完成文が表示されます。")
                            .foregroundStyle(.secondary)
                    }
                } header: { Text("この内容を使います") } footer: { Text("枠内を上下にスクロールして、全文を確認できます。") }
                if model.isComposing {
                    Text("文字の変換を確定してから、完成文を確認してください。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.error { Section { WorkspaceErrorView(error: error) } }
                if WorkspacePresentation.canRecoverIndependently(model.error) || model.hasIndependentRecovery {
                    Section {
                        Button("今の完成文を別の文章として保存") { startTask(.independent) }
                            .disabled(model.output == nil || model.isComposing)
                            .accessibilityIdentifier("workspace.use.recover")
                        Text("元の文章と元の作業はそのまま残します。保存後、この完成文を確認してコピーできます。")
                            .font(.footnote).foregroundStyle(.secondary)
                        if model.hasIndependentRecovery {
                            Text("独立保存のための作業も残しています。中断後は「作業中」の「作成中」から完成文を確認して再開できます。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if model.draft != nil && !model.copied {
                    Section {
                        Text("同じ相手・用件へ繰り返し使う場合だけ、完成文を別の文章として残せます。")
                            .font(.footnote).foregroundStyle(.secondary)
                        NativeDocumentField(text: Binding(get: { model.title }, set: { model.updateTitle($0) }),
                                            composing: Binding(get: { model.isComposing }, set: { model.isComposing = $0 }),
                                            identifier: "workspace.use.completionTitle", label: "完成文の名前", singleLine: true)
                            .frame(minHeight: 48)
                        Button("完成文を別の文章として保存") { startTask(.saveCompletion) }
                            .disabled(model.output == nil || model.isComposing)
                            .accessibilityIdentifier("workspace.use.saveCompletion")
                    } header: { Text("繰り返し使う完成文を残す") }
                    Section {
                        if model.discardsLocalInputOnly {
                            Text("別の画面の作業は変更せず、この画面の入力だけを破棄して閉じられます。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button(model.discardsLocalInputOnly ? "この画面の入力を破棄して閉じる" : "今回の差し替えを破棄", role: .destructive) { confirmDiscard = true }
                            .accessibilityIdentifier("workspace.use.discard")
                    }
                }
                if model.completionSaved {
                    Text("独立した文章として保存しました。ピン留めするとキーボードからも使えます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(model.busy || model.copied)
            .navigationTitle(model.names.isEmpty ? "内容を確認" : "差し替えて確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.copied ? "完了" : "閉じる") { startTask(.close) }
                        .disabled(model.busy || model.isComposing)
                        .accessibilityIdentifier("workspace.use.close")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if model.copied {
                        Label("コピーしました。入力先に戻ってペーストしてください。", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .accessibilityIdentifier("workspace.use.receipt")
                        if model.error != nil {
                            Text("作業中の片付けができませんでした。コピーは完了しているため、再実行しません。")
                                .font(.footnote)
                        }
                    }
                    if !model.copied {
                        Button("この内容をコピー", systemImage: "doc.on.doc") { startTask(.copy) }
                            .buttonStyle(WorkspacePrimaryButtonStyle())
                            .frame(maxWidth: .infinity)
                            .controlSize(.large)
                            .disabled(model.output == nil || model.busy || model.isComposing)
                            .accessibilityIdentifier("workspace.use.copy")
                        Text("自動で貼り付けたり、送信したりはしません。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.regularMaterial)
            }
            .confirmationDialog(model.discardsLocalInputOnly ? "この画面の入力だけを破棄しますか？ 別の画面の作業とひな型は変更しません。" : "今回の入力を破棄しますか？ ひな型は変わりません。", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button(model.discardsLocalInputOnly ? "この画面の入力だけを破棄して閉じる" : "今回の差し替えを破棄", role: .destructive) { startTask(.discard) }
            }
        }
        .interactiveDismissDisabled()
        .alert(model.copied ? "コピーは完了しています" : "操作を完了できませんでした", isPresented: Binding(get: { shownFailure != nil }, set: { if !$0 { shownFailure = nil } }), presenting: shownFailure) { _ in
            Button("確認に戻る", role: .cancel) {}
        } message: { error in
                Text(model.copied ? "コピーは完了しました。作業中の片付けができなかったため、入力を残しています。入力先へ戻ってペーストしてください。コピーは再実行しません。" : WorkspacePresentation.error(error))
                .accessibilityIdentifier("workspace.failure.message")
        }
        .onChange(of: model.error) { _, _ in presentFailure() }
        .onChange(of: model.isComposing) { _, composing in
            if !composing { presentFailure() }
        }
        .task(id: model.draft?.sequence) { await model.checkpoint() }
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
        tasks.start(id: "workspace.use.action", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            switch action {
            case .checkpoint: await model.checkpoint()
            case .close:
                guard await model.suspend() else { presentFailure(); return }
                try cancellation.check()
                await onFinished()
            case .copy: await model.copy(using: delivery); presentFailure()
            case .saveCompletion: _ = await model.saveCompletion(); presentFailure()
            case .independent: _ = await model.saveIndependentCompletion(); presentFailure()
            case .discard:
                guard await model.discard() else { presentFailure(); return }
                await onFinished()
            }
        }
    }
}
