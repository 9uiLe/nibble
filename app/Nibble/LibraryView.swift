import SwiftUI
import Tasking
import ScopedAnimation

struct LibraryView: View {
    @State private var model = LibraryModel()
    @State private var taskOwner = LibraryTaskOwner()
    @State private var permanentDeletion: SnippetSummary?
    @State private var showsAbout = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var library = model
        NavigationStack {
            List {
                Section {
                    searchField
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    if model.filter != .trash {
                        Picker("表示する項目", selection: $library.filter) {
                            Text("すべて").tag(LibraryFilter.all)
                            Text("ピン留め").tag(LibraryFilter.pinned)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    }
                }
                .listRowSeparator(.hidden)

                if !model.drafts.isEmpty && model.filter != .trash && model.query.isEmpty {
                    Section {
                        ForEach(model.drafts) { draft in
                            Button { model.editor = draft } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("下書きを再開").font(.subheadline.weight(.semibold))
                                        Text(draft.title.isEmpty ? "編集中のスニペット" : draft.title)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                } icon: { Image(systemName: "square.and.pencil") }
                            }
                            .accessibilityIdentifier("draft.\(draft.id)")
                        }
                    }
                }

                if let error = model.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                        Button("再試行") { startTask(.refresh) }
                    }
                }

                if model.items.isEmpty && !model.loading && model.error == nil {
                    emptyState.listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(model.items) { item in
                            snippetRow(item)
                        }
                        if model.hasMore {
                            Button("さらに表示") { model.limit += 100 }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    } header: {
                        HStack {
                            Text(sectionTitle)
                            Spacer()
                            if model.loading { ProgressView().controlSize(.mini) }
                        }
                    } footer: {
                        if model.filter == .trash { Text("自動では消えません。必要な項目を復元できます。") }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.nibbleCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(model.filter == .trash ? "削除した項目" : "nibble")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.filter == .trash {
                        Button("一覧へ戻る", systemImage: "chevron.left") { model.filter = .all }
                            .accessibilityIdentifier("library.back")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("その他", systemImage: "ellipsis") {
                        Button("削除した項目", systemImage: "trash") { model.query = ""; model.filter = .trash }
                            .accessibilityIdentifier("library.trash")
                        Button("nibbleについて", systemImage: "info.circle") { showsAbout = true }
                    }
                    .accessibilityIdentifier("library.menu")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("新しいスニペット", systemImage: "plus") { startTask(.open(nil)) }
                        .accessibilityIdentifier("library.add")
                        .keyboardShortcut("n", modifiers: .command)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down") { searchFocused = false }
                        .accessibilityIdentifier("library.keyboard.dismiss")
                }
            }
            .safeAreaInset(edge: .bottom) {
                AnimationScope(.easeOut(duration: reduceMotion ? 0 : 0.16), value: model.notice != nil, name: "Library.Notice") {
                    if let notice = model.notice {
                        HStack(spacing: 16) {
                            Label(notice, systemImage: "checkmark.circle.fill").font(.subheadline.weight(.medium))
                                .accessibilityIdentifier("library.notice")
                            Spacer(minLength: 0)
                            if let id = model.undoID {
                                Button("元に戻す") { startTask(.restore(id)) }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("library.undo")
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 6)
                        .background(.regularMaterial, in: .rect(cornerRadius: 20))
                        .padding(.horizontal, 16).padding(.bottom, 8)
                        .transition(.opacity)
                    }
                }
            }
            .sheet(item: $library.editor, onDismiss: { startTask(.refresh) }) { draft in
                SnippetEditor(draft: draft, store: model.store)
            }
            .sheet(isPresented: $showsAbout) { AboutView() }
            .confirmationDialog("完全に削除しますか？", isPresented: Binding(get: { permanentDeletion != nil }, set: { if !$0 { permanentDeletion = nil } }), titleVisibility: .visible) {
                if let item = permanentDeletion {
                    Button("完全に削除", role: .destructive) { startTask(.permanentlyDelete(item.id)); permanentDeletion = nil }
                }
            } message: { Text("この項目と対応する下書きは元に戻せません。") }
        }
        .tint(.nibbleAccent)
        .detectAnimationLeaks()
        // Keep native presentation transactions outside app content; local scopes own its animation.
        .animationBarrier(warnsOnLeaks: false)
        .sensoryFeedback(.success, trigger: model.feedback)
        .task(id: model.noticeID) {
            if let id = model.noticeID { await model.expireNotice(id: id) }
        }
        .onAppear { startTask(.refresh) }
        .onChange(of: "\(model.query)|\(model.filter.rawValue)|\(model.limit)") { startTask(.refresh) }
        .onChange(of: model.query) { model.limit = 100 }
        .onChange(of: model.filter) { model.limit = 100 }
        .onChange(of: scenePhase) {
            if scenePhase == .active { startTask(.refresh) }
            else if scenePhase == .background { taskOwner.endScreen(); model.clearNotice() }
        }
        .onOpenURL { url in
            guard let route = AppRoute(url: url) else { return }
            if model.editor != nil { return } // Never replace an in-progress edit.
            model.filter = .all
            model.query = ""
            if route == .create { startTask(.open(nil)) }
        }
        .privacySensitive()
        .overlay {
            if scenePhase != .active {
                Color.nibbleCanvas.ignoresSafeArea().overlay {
                    Text("nibble").font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(Color.nibbleAccent)
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func startTask(_ action: LibraryTaskOwner.Action) {
        if case .open = action { searchFocused = false }
        taskOwner.startTask(action, on: model)
    }

    private var sectionTitle: String {
        if model.filter == .trash { return "削除した項目" }
        return model.query.isEmpty ? "手元のスニペット" : "検索結果"
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("タイトルや本文を検索", text: $model.query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("library.search")
                .accessibilityLabel("スニペットを検索")
            if !model.query.isEmpty {
                Button("検索をクリア", systemImage: "xmark.circle.fill") { model.query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("library.search.clear")
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 50)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 16))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(model.filter == .trash ? "削除した項目はありません" : (!model.query.isEmpty ? "見つかりませんでした" : (model.filter == .pinned ? "よく使う言葉を、手前に。" : "言葉を、すぐ手元に。")),
                  systemImage: model.filter == .trash ? "trash" : (model.query.isEmpty ? "text.quote" : "magnifyingglass"))
        } description: {
            Text(model.filter == .trash ? "削除したスニペットはここから復元できます。" : (!model.query.isEmpty ? "別の言葉や、短い語句で探してみてください。" : (model.filter == .pinned ? "項目を長押ししてピン留めすると、すぐに見つかります。" : "よく使う言葉を保存して、\n次からはワンタップでコピー。")))
        } actions: {
            if model.query.isEmpty && model.filter == .all {
                Button("最初のスニペットを作る") { startTask(.open(nil)) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("library.createFirst")
            }
        }
        .padding(.vertical, 30)
    }

    private func snippetRow(_ item: SnippetSummary) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { if model.filter != .trash { startTask(.open(item.id)) } } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if item.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.nibbleAccent) }
                        Text(item.displayTitle).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    }
                    if !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(item.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(model.filter == .trash)
            .accessibilityIdentifier("snippet.\(item.id)")
            .accessibilityLabel(item.pinned ? "ピン留め、\(item.displayTitle)" : item.displayTitle)
            .accessibilityHint(model.filter == .trash ? "" : "編集します")

            if model.filter == .trash {
                Button("復元", systemImage: "arrow.uturn.backward") { startTask(.restore(item.id)) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("restore.\(item.id)")
            } else {
                Button { startTask(.copy(item.id)) } label: {
                    Image(systemName: "doc.on.doc").font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                        .background(Color.nibbleAccent.opacity(0.09), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(item.displayTitle)をコピー")
                .accessibilityIdentifier("copy.\(item.id)")
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            if model.filter == .trash {
                Button("復元", systemImage: "arrow.uturn.backward") { startTask(.restore(item.id)) }
                Button("完全に削除", systemImage: "trash", role: .destructive) { permanentDeletion = item }
            } else {
                Button(item.pinned ? "ピン留めを外す" : "ピン留め", systemImage: item.pinned ? "pin.slash" : "pin") { startTask(.pin(item)) }
                Button("編集", systemImage: "square.and.pencil") { startTask(.open(item.id)) }
                Button("削除", systemImage: "trash", role: .destructive) { startTask(.delete(item.id)) }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if model.filter == .trash {
                Button("完全に削除", role: .destructive) { permanentDeletion = item }
            } else {
                Button("削除", role: .destructive) { startTask(.delete(item.id)) }
                Button(item.pinned ? "解除" : "ピン留め", systemImage: item.pinned ? "pin.slash" : "pin") { startTask(.pin(item)) }.tint(.nibbleAccent)
            }
        }
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("言葉を、すぐ手元に。").font(.title2.weight(.semibold))
                    Text("一覧のコピーボタンで本文をコピー。項目をタップすると編集、長押しするとピン留めや削除ができます。")
                }
                Section("ほかのアプリから") {
                    Text("テキストやURLの共有メニューでnibbleを選ぶと、内容を保存できます。共有先に表示されない場合は「その他」から追加してください。")
                    Text("ショートカットの「URLを開く」に、一覧は nibble://library、作成は nibble://new を指定できます。ホーム画面やコントロールセンターに置くと、すぐに呼び出せます。")
                }
                Section("データについて") {
                    Text("スニペットと下書きはこの端末に保存します。コピーした本文はこの端末内で利用できます。")
                    Text("削除した項目は自動で消えません。「削除した項目」から復元、または完全に削除できます。アプリを削除すると保存データも失われます。")
                    Text("アカウント、広告、アクセス解析はありません。")
                }
            }
            .navigationTitle("nibbleについて").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }.tint(.nibbleAccent)
    }
}

/// Owns finite UI requests across presentation changes in the library scene.
/// Business operations remain directly awaitable on LibraryModel.
@MainActor
final class LibraryTaskOwner {
    private let tasks = ViewTaskStore()

    enum Action {
        case refresh, open(UUID?), copy(UUID), pin(SnippetSummary)
        case delete(UUID), restore(UUID), permanentlyDelete(UUID)

        var id: ActionID {
            switch self {
            case .refresh: "library.refresh"
            case .open: "library.open"
            case .copy: "library.copy"
            case .pin(let item): ActionID("library.pin.\(item.id)")
            case .delete(let id): ActionID("library.delete.\(id)")
            case .restore(let id): ActionID("library.restore.\(id)")
            case .permanentlyDelete(let id): ActionID("library.permanentlyDelete.\(id)")
            }
        }

        var lifetime: ActionLifetime {
            if case .open = self { return .screenBound }
            return .sceneBound
        }

        var policy: TaskStartPolicy {
            switch self {
            case .refresh, .copy: .cancelExisting
            default: .ignoreNew
            }
        }
    }

    @discardableResult
    func startTask(_ action: Action, on model: LibraryModel) -> TaskStartOutcome {
        tasks.start(id: action.id, lifetime: action.lifetime, policy: action.policy) { [weak model] cancellation in
            try cancellation.check()
            guard let model else { return }
            switch action {
            case .refresh: await model.refresh()
            case .open(let id): await model.open(id: id)
            case .copy(let id): await model.copy(id)
            case .pin(let item): await model.pin(item)
            case .delete(let id): await model.delete(id)
            case .restore(let id): await model.restore(id)
            case .permanentlyDelete(let id): await model.permanentlyDelete(id)
            }
        }
    }

    func endScreen() { tasks.cancel(lifetime: .screenBound) }
    func waitForIdle() async { await tasks.waitForIdle() }
}
