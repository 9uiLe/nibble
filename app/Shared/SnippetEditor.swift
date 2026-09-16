import SwiftUI
import Tasking
import ScopedAnimation

struct SnippetEditor: View {
    @State private var model: EditorModel
    @State private var confirmsDiscard = false
    @State private var tasks = ViewTaskStore()
    private static var finishAction: ActionID { "editor.finish" }
    private enum Field { case title, body }
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let complete: (@MainActor () -> Void)?

    init(draft: Draft, store: SnippetStore, complete: (@MainActor () -> Void)? = nil) {
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
                        Text("タイトル").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("任意・見つけやすい名前", text: $editor.title, axis: .vertical)
                            .font(.title2.weight(.semibold))
                            .focused($focus, equals: .title)
                            .accessibilityIdentifier("editor.title")
                            .accessibilityLabel("タイトル")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("本文").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            PasteButton(payloadType: String.self) { texts in
                                if let text = texts.first { model.body += text }
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("本文にペースト")
                        }
                        // A growing native multiline field lets the entire page scroll on small screens.
                        TextField("繰り返し使う言葉を、ここに。", text: $editor.body, axis: .vertical)
                            .font(.body)
                            .lineLimit(10...)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .body)
                            .accessibilityIdentifier("editor.body")
                            .accessibilityLabel("本文")
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
                    Text("閉じても下書きが残ります。空白と改行も、そのまま保存します。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
                .animationBarrier()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.nibbleCanvas)
            .navigationTitle(model.draft.snippetID == nil ? "新しいスニペット" : "スニペットを編集")
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
                    if model.phase == .finishing { ProgressView().accessibilityLabel("保存中") }
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
            } message: { Text("保存済みのスニペットは変わりません。") }
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
