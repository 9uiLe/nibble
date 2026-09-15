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
                            Button { startTask(.open(.draft(draft.id))) } label: {
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
                            Button("さらに表示") { model.showMore() }
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
                    Button("新しいスニペット", systemImage: "plus") { startTask(.open(.new)) }
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
                            Label(notice.message, systemImage: "checkmark.circle.fill").font(.subheadline.weight(.medium))
                                .accessibilityIdentifier("library.notice")
                            Spacer(minLength: 0)
                            if let id = notice.undoID {
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
        .task(id: model.notice?.id) {
            if let id = model.notice?.id { await model.expireNotice(id: id) }
        }
        .onAppear { startTask(.refresh) }
        .onChange(of: model.request) { startTask(.refresh) }
        .onChange(of: scenePhase) {
            if scenePhase == .active { startTask(.refresh) }
            else if scenePhase == .background { taskOwner.endScreen(); model.clearNotice() }
        }
        .onOpenURL { url in
            guard let route = AppRoute(url: url) else { return }
            if model.editor != nil { return } // Never replace an in-progress edit.
            model.filter = .all
            model.query = ""
            if route == .create { startTask(.open(.new)) }
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

    private var emptyContent: (title: String, symbol: String, message: String) {
        if model.filter == .trash {
            return ("削除した項目はありません", "trash", "削除したスニペットはここから復元できます。")
        }
        if !model.query.isEmpty {
            return ("見つかりませんでした", "magnifyingglass", "別の言葉や、短い語句で探してみてください。")
        }
        if model.filter == .pinned {
            return ("よく使う言葉を、手前に。", "text.quote", "項目を長押ししてピン留めすると、すぐに見つかります。")
        }
        return ("言葉を、すぐ手元に。", "text.quote", "よく使う言葉を保存して、\n次からはワンタップでコピー。")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyContent.title, systemImage: emptyContent.symbol)
        } description: {
            Text(emptyContent.message)
        } actions: {
            if model.query.isEmpty && model.filter == .all {
                Button("最初のスニペットを作る") { startTask(.open(.new)) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("library.createFirst")
            }
        }
        .padding(.vertical, 30)
    }

    private func snippetRow(_ item: SnippetSummary) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { if model.filter != .trash { startTask(.open(.snippet(item.id))) } } label: {
                SnippetRowContent(title: item.title, preview: item.preview, pinned: item.pinned)
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
                Button("編集", systemImage: "square.and.pencil") { startTask(.open(.snippet(item.id))) }
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

