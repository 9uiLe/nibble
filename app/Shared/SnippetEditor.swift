import AppMacros
import SwiftUI
import Tasking
import ScopedAnimation

@Equatable
struct SnippetEditor: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    @State private var model: EditorModel
    @State private var confirmsDiscard = false
    @State private var tasks = ViewTaskStore()
    private static var finishAction: ActionID { "editor.finish" }
    private enum Field { case title, body }
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let complete: (@MainActor () -> Void)?

    init(draft: Draft, store: any DraftEditing, complete: (@MainActor () -> Void)? = nil) {
        _model = State(initialValue: EditorModel(draft: draft, store: store))
        self.complete = complete
    }

    var body: some View {
        @Bindable var editor = model
        let snapshot = model.draft
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("タイトル（任意）").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("例：お礼のメール", text: $editor.title, axis: .vertical)
                            .font(.title2.weight(.semibold))
                            .focused($focus, equals: .title)
                            .accessibilityIdentifier("editor.title")
                            .accessibilityLabel("タイトル（任意）")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("本文").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                PasteButton(payloadType: String.self) { texts in
                                    if let text = texts.first { model.body += text }
                                }
                                .labelStyle(.iconOnly)
                                .controlSize(.large)
                                .accessibilityLabel("本文の末尾にペースト")
                                Text("末尾に追加").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if !model.hasBody {
                            Text("保存するには本文を入力してください。空白や改行だけでは保存できません。")
                                .font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("editor.bodyRequirement")
                        }
                        // A growing native multiline field lets the entire page scroll on small screens.
                        TextField("保存したい文章やURLを入力", text: $editor.body, axis: .vertical)
                            .font(.body)
                            .lineLimit(10...)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .body)
                            .accessibilityIdentifier("editor.body")
                            .accessibilityLabel("本文")
                        Text("空白や改行は、そのまま保存されます。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("長さの上限はタイトル512バイト、本文1 MB（1,000,000バイト）です。どちらもUTF-8で数えるため、文字によって使うバイト数が異なります。")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("editor.lengthLimit")
                    }
                    if let failure = model.failure {
                        Label(failure.message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red).font(.callout)
                            .accessibilityIdentifier("editor.error")
                        if failure.canSaveAsNew {
                            Button("新しい項目として保存") { startTask(.saveAsNew) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    Text("「保存」を押すと、一覧やキーボードから使えます。「閉じる」を押すと、入力した内容が下書きに残ります。空の新規入力や、変更していない項目は下書きに残りません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
                .animationBarrier()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.nibbleCanvas)
            .navigationTitle(model.draft.snippetID == nil ? "新規作成" : "項目を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", systemImage: "xmark") { startTask(.keep) }
                        .accessibilityIdentifier("editor.close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark") { startTask(.save) }
                        .fontWeight(.semibold)
                        .disabled(!model.canSave)
                        .accessibilityIdentifier("editor.save")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Menu("その他", systemImage: "ellipsis") {
                        ShareLink(item: model.body) { Label("本文を共有", systemImage: "square.and.arrow.up") }
                            .disabled(model.body.isEmpty)
                        Button("下書きを破棄", systemImage: "trash", role: .destructive) { confirmsDiscard = true }
                            .accessibilityIdentifier("editor.discard")
                    }
                    .accessibilityIdentifier("editor.more")
                    Spacer()
                    if case .finishing(let operation) = model.phase {
                        ProgressView(operation.progressTitle)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down") { focus = nil }
                        .accessibilityIdentifier("editor.keyboard.dismiss")
                }
            }
            .disabled(model.phase != .editing)
            .confirmationDialog("この下書きを破棄しますか？", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("下書きを破棄", role: .destructive) {
                    startTask(.discard)
                }
                .accessibilityIdentifier("editor.confirmDiscard")
            } message: { Text("この下書きの内容は元に戻せません。保存済みの項目は変わりません。") }
        }
        .tint(.nibbleAccent)
        .detectAnimationLeaks()
        // Keep native presentation transactions outside app content; local scopes own its animation.
        .animationBarrier(warnsOnLeaks: false)
        .task(id: snapshot.sequence) {
            if snapshot.sequence > 0 { await model.persist(snapshot) }
        }
        .onDisappear { tasks.cancel(lifetime: .screenBound) }
        .interactiveDismissDisabled()
        .privacySensitive()
        .overlay {
            // A share extension has no app scene and can report background while visible.
            if complete == nil && scenePhase == .background {
                Color.nibbleCanvas.ignoresSafeArea().overlay { Text("nibble").font(.largeTitle.weight(.bold)) }
            }
        }
    }

    private func startTask(_ operation: EditorModel.FinishOperation) {
        let editor = model
        let completion = complete
        let dismiss = dismiss
        tasks.start(id: Self.finishAction, lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            let succeeded = await editor.finish(operation)
            // A completed persistence operation must finish the editor even if cancellation arrived meanwhile.
            if succeeded {
                if let completion { completion() } else { dismiss() }
            }
        }
    }


}
