import AppMacros
import SwiftUI
import Tasking

@MainActor @Equatable
struct PromptDetailView: View {
    private enum Action { case copy, edit, rename, delete, close }
    private enum Dialog { case rename, delete, failure(WorkspaceError) }
    private let inputRevision = UUID()
    @SkipEquatable let model: PromptSessionModel
    @SkipEquatable let delivery: any TextDelivery
    let onClosed: @MainActor () async -> Void
    let onDeleted: @MainActor (TextCard) async -> Void
    @State private var tasks = ViewTaskStore()
    @State private var menuOpen = false
    @State private var dialog: Dialog?

    private var dialogTitle: String {
        switch dialog {
        case .rename: "タイトルを変更"
        case .delete: "プロンプトを削除しますか？"
        case .failure, .none: "操作を完了できませんでした"
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 24) {
                HStack(spacing: 0) {
                    HStack {
                        Button { startTask(.close) } label: { PromptIconLabel(title: "一覧へ戻る", symbol: "chevron.left") }
                            .buttonStyle(.plain).accessibilityIdentifier("prompt.back")
                        Spacer(minLength: 0)
                    }
                    .frame(width: 96)
                    Text(verbatim: WorkspacePresentation.title(model.card))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("prompt.title")
                    HStack(spacing: 8) {
                        Button { startTask(.edit) } label: {
                            Label("本文を編集", systemImage: "pencil")
                                .labelStyle(.iconOnly).font(.system(size: 20))
                                .frame(width: 44, height: 44).contentShape(Circle())
                        }
                        .accessibilityIdentifier("prompt.edit")
                        Button { menuOpen = true } label: {
                            Label("その他の操作", systemImage: "ellipsis")
                                .labelStyle(.iconOnly).font(.system(size: 20))
                                .frame(width: 44, height: 44).contentShape(Circle())
                        }
                        .accessibilityIdentifier("prompt.more")
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .disabled(model.busy)
                NativeDocumentPreview(text: model.card.body, identifier: "prompt.body", style: .prompt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottomTrailing) {
                Button { startTask(.copy) } label: {
                    Label(model.copied ? "コピーしました" : "本文をコピー", systemImage: model.copied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.iconOnly).font(.system(size: 20))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(width: 56, height: 56).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Color.primary.opacity(0.9)).interactive(), in: .circle)
                .padding(.trailing, 24).padding(.bottom, 2)
                .disabled(model.busy)
                .accessibilityIdentifier("prompt.copy")
            }
            .accessibilityHidden(menuOpen)
            .allowsHitTesting(!menuOpen)
            if menuOpen {
                Button { menuOpen = false } label: { Color.black.opacity(0.05) }
                    .buttonStyle(.plain).ignoresSafeArea()
                    .accessibilityLabel("メニューを閉じる")
                    .accessibilityIdentifier("prompt.menu.close")
                PromptDetailMenu {
                    menuOpen = false
                    dialog = .rename
                } delete: {
                    menuOpen = false
                    dialog = .delete
                }
                .padding(.top, 66).padding(.trailing, 24)
            }
        }
        .foregroundStyle(WorkspaceStyle.text)
        .background(Color(uiColor: .systemBackground))
        .tint(.primary)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: Binding(get: { model.editor }, set: { _ in })) { editor in
            PromptEditorView(model: editor) { saved in await model.finishedEditing(saved: saved) }
        }
        .alert(dialogTitle, isPresented: Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } }), presenting: dialog) { dialog in
            switch dialog {
            case .rename:
                TextField("タイトル", text: Binding(get: { model.renameTitle }, set: { model.renameTitle = $0 }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("キャンセル", role: .cancel) { model.renameTitle = model.card.title }
                Button("保存") { startTask(.rename) }
                    .disabled(model.renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .delete:
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) { startTask(.delete) }
            case .failure:
                Button("閉じる", role: .cancel) {}
            }
        } message: { dialog in
            switch dialog {
            case .delete: Text("「\(WorkspacePresentation.title(model.card))」を一覧から削除します。")
            case .failure(let error): Text(PromptPresentation.error(error))
            case .rename: EmptyView()
            }
        }
        .onChange(of: model.error) { _, error in
            if let error { dialog = .failure(error) }
        }
        .onDisappear { tasks.cancel(lifetime: .screenBound) }
    }

    private func startTask(_ action: Action) {
        tasks.start(id: "prompt.detail.action", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            switch action {
            case .copy: await model.copy(using: delivery)
            case .edit: await model.beginEditing()
            case .rename: _ = await model.rename()
            case .delete:
                if let deleted = await model.trash() { await onDeleted(deleted) }
            case .close: await onClosed(); return
            }
            if let error = model.error { dialog = .failure(error) }
        }
    }
}
