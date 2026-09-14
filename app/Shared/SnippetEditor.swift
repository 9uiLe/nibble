import SwiftUI

struct SnippetEditor: View {
    @State private var model: EditorModel
    @State private var confirmsDiscard = false
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
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red).font(.callout)
                            .accessibilityIdentifier("editor.error")
                        if model.conflict {
                            Button("新しい項目として保存") { save(asNew: true) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    Text("閉じても下書きが残ります。空白と改行も、そのまま保存します。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.nibbleCanvas)
            .navigationTitle(model.draft.snippetID == nil ? "新しいスニペット" : "スニペットを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", systemImage: "xmark") { close() }
                        .accessibilityIdentifier("editor.close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark") { save() }
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
                    if model.busy { ProgressView().accessibilityLabel("保存中") }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down") { focus = nil }
                        .accessibilityIdentifier("editor.keyboard.dismiss")
                }
            }
            .disabled(model.busy)
            .confirmationDialog("この下書きを破棄しますか？", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("下書きを破棄", role: .destructive) {
                    Task { if await model.discard() { finish() } }
                }
                .accessibilityIdentifier("editor.confirmDiscard")
            } message: { Text("保存済みのスニペットは変わりません。") }
        }
        .tint(.nibbleAccent)
        .interactiveDismissDisabled()
        .privacySensitive()
        .overlay {
            // A share extension has no app scene and can report background while visible.
            if complete == nil && scenePhase == .background {
                Color.nibbleCanvas.ignoresSafeArea().overlay { Text("nibble").font(.largeTitle.weight(.bold)) }
            }
        }
    }

    private func finish() {
        if let complete { complete() } else { dismiss() }
    }
    private func close() { Task { if await model.keepForLater() { finish() } } }
    private func save(asNew: Bool = false) { Task { if await model.save(asNew: asNew) { finish() } } }
}

extension Color {
    static let nibbleAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.64, blue: 0.39, alpha: 1) : UIColor(red: 0.64, green: 0.24, blue: 0.08, alpha: 1)
    })
    static let nibbleCanvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.08, green: 0.085, blue: 0.08, alpha: 1) : UIColor(red: 0.975, green: 0.968, blue: 0.95, alpha: 1)
    })
}
