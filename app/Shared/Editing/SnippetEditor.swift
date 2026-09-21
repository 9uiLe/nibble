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
    @State private var showsHelp = false
    @State private var focusBeforeHelp: Field?
    @State private var hasSetInitialFocus = false
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
                    if complete != nil {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("共有された内容を確認").font(.nibbleTitle)
                                Text("編集してからnibbleに保存できます。")
                                    .font(.nibbleBody).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundStyle(Color.nibbleAccent)
                        }
                        .accessibilityIdentifier("editor.sharedContent")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("タイトル（任意）").font(.nibbleTitle).foregroundStyle(.secondary)
                        TextField("例：お礼のメール", text: $editor.title, axis: .vertical)
                            .font(.nibbleTitle)
                            .focused($focus, equals: .title)
                            .accessibilityIdentifier("editor.title")
                            .accessibilityLabel("タイトル（任意）")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("本文").font(.nibbleTitle).foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                PasteButton(payloadType: String.self) { texts in
                                    if let text = texts.first { model.body += text }
                                }
                                .labelStyle(.titleAndIcon)
                                .controlSize(.large)
                                .accessibilityLabel("本文の末尾にペースト")
                                Text("末尾に追加").font(.nibbleBody).foregroundStyle(.secondary)
                            }
                        }
                        if !model.hasBody {
                            Text("本文を入力すると保存できます。空白や改行だけでは保存できません。")
                                .font(.nibbleBody).foregroundStyle(.secondary)
                                .accessibilityIdentifier("editor.bodyRequirement")
                        }
                        // A growing native multiline field lets the entire page scroll on small screens.
                        TextField("保存したい文章やURLを入力", text: $editor.body, axis: .vertical)
                            .font(.nibbleBody)
                            .lineLimit(10...)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .body)
                            .accessibilityIdentifier("editor.body")
                            .accessibilityLabel("本文")
                        Label("空白や改行は、そのまま保存されます。", systemImage: "checkmark.shield")
                            .font(.nibbleBody).foregroundStyle(.secondary)
                    }
                    if let failure = model.failure {
                        Label(failure.message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red).font(.nibbleBody)
                            .accessibilityIdentifier("editor.error")
                        if failure.canSaveAsNew {
                            Button("新しい項目として保存") { startTask(.saveAsNew) }
                                .font(.nibbleTitle)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .accessibilityIdentifier("editor.saveAsNew")
                        }
                    }
                }
                .padding(24)
                .animationBarrier()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.nibbleCanvas)
            .safeAreaInset(edge: .top, spacing: 0) { editorHeader }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focus == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider().padding(.bottom, 8)
                        Text("**保存**すると、一覧やキーボードで使えます。")
                        if complete != nil {
                            Text("**閉じる**と、下書きを残して共有元に戻ります。")
                        } else {
                            Text("**閉じる**と、編集内容が下書きに残ります。")
                        }
                    }
                    .font(.nibbleBody).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.nibbleCanvas)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Menu("その他", systemImage: "ellipsis") {
                        ShareLink(item: model.body) { Label("本文を共有", systemImage: "square.and.arrow.up") }
                            .disabled(model.body.isEmpty)
                        Button("下書きを破棄", systemImage: "trash", role: .destructive) { confirmsDiscard = true }
                            .accessibilityIdentifier("editor.discard")
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("その他")
                    .accessibilityIdentifier("editor.more")
                    Spacer()
                    if case .finishing(let operation) = model.phase {
                        ProgressView {
                            Text(operation.progressTitle).font(.nibbleBody)
                        }
                    } else {
                        Button { showHelp() } label: {
                            HStack(spacing: 6) {
                                Text("入力の上限と保存について")
                                Image(systemName: "chevron.right")
                            }
                            .font(.nibbleBody)
                            .frame(minHeight: 44)
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("editor.help")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("入力の上限と保存について") { showHelp() }
                        .font(.nibbleBody)
                        .accessibilityIdentifier("editor.keyboard.help")
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
            .sheet(isPresented: $showsHelp, onDismiss: { focus = focusBeforeHelp }) {
                EditorHelpView()
            }
        }
        .tint(.nibbleAccent)
        .detectAnimationLeaks()
        // Keep native presentation transactions outside app content; local scopes own its animation.
        .animationBarrier(warnsOnLeaks: false)
        .onAppear {
            guard !hasSetInitialFocus else { return }
            hasSetInitialFocus = true
            if complete == nil && model.draft.snippetID == nil && model.title.isEmpty && model.body.isEmpty {
                focus = .body
            }
        }
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

    private var editorHeader: some View {
        HStack(spacing: 12) {
            Button("閉じる") { startTask(.keep) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("editor.close")
            Text(complete != nil ? "共有から保存" : model.draft.snippetID == nil ? "新規作成" : "項目を編集")
                .font(.nibbleTitle)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Button("保存") { startTask(.save) }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color.nibbleCanvas)
                .fontWeight(.semibold)
                .disabled(!model.canSave)
                .accessibilityIdentifier("editor.save")
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.nibbleCanvas)
        .animationBarrier()
    }

    private func showHelp() {
        focusBeforeHelp = focus
        focus = nil
        showsHelp = true
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

@Equatable
private struct EditorHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("入力の上限").font(.nibbleTitle)
                        Text("タイトルは任意で512バイトまで、本文は1 MB（1,000,000バイト）まで入力できます。")
                            .accessibilityIdentifier("editor.lengthLimit")
                        Text("UTF-8で数えるため、文字によって使うバイト数が異なります。空白や改行は、そのまま保存されます。")
                        Text("本文が空、または空白や改行だけの場合は保存できません。")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("保存と下書き").font(.nibbleTitle)
                        Text("「保存」を押すと、一覧やキーボードから使えます。")
                        Text("「閉じる」を押すと、入力した内容が下書きに残ります。空の新規入力や、変更していない項目は下書きに残りません。")
                        Text("下書きは一覧の「下書き」から再開できます。不要な下書きは、編集画面の「その他」から破棄できます。保存済みの項目は変わりません。")
                    }
                }
                .font(.nibbleBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(Color.nibbleCanvas)
            .navigationTitle("入力の上限と保存について")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("戻る") { dismiss() }
                        .accessibilityLabel("編集に戻る")
                        .accessibilityIdentifier("editor.help.close")
                }
            }
        }
        .tint(.nibbleAccent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .animationBarrier()
    }
}
