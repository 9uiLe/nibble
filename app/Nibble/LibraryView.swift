import SwiftUI

struct LibraryView: View {
    @State private var model = LibraryModel()
    @State private var permanentDeletion: SnippetSummary?
    @State private var showsAbout = false
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
                        Button("再試行") { Task { await model.refresh() } }
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
                    Button("新しいスニペット", systemImage: "plus") { openEditor() }
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
                if let notice = model.notice {
                    HStack(spacing: 16) {
                        Label(notice, systemImage: "checkmark.circle.fill").font(.subheadline.weight(.medium))
                            .accessibilityIdentifier("library.notice")
                        Spacer(minLength: 0)
                        if let id = model.undoID {
                            Button("元に戻す") { model.restore(id) }
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("library.undo")
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 6)
                    .background(.regularMaterial, in: .rect(cornerRadius: 20))
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
            .sheet(item: $library.editor, onDismiss: { Task { await model.refresh() } }) { draft in
                SnippetEditor(draft: draft, store: model.store)
            }
            .sheet(isPresented: $showsAbout) { AboutView() }
            .confirmationDialog("完全に削除しますか？", isPresented: Binding(get: { permanentDeletion != nil }, set: { if !$0 { permanentDeletion = nil } }), titleVisibility: .visible) {
                if let item = permanentDeletion {
                    Button("完全に削除", role: .destructive) { model.permanentlyDelete(item.id); permanentDeletion = nil }
                }
            } message: { Text("この項目と対応する下書きは元に戻せません。") }
        }
        .tint(.nibbleAccent)
        .sensoryFeedback(.success, trigger: model.feedback)
        .task(id: "\(model.query)|\(model.filter.rawValue)|\(model.limit)") { await model.refresh() }
        .onChange(of: model.query) { model.limit = 100 }
        .onChange(of: model.filter) { model.limit = 100 }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await model.refresh() } }
        }
        .onOpenURL { url in
            guard let route = AppRoute(url: url) else { return }
            if model.editor != nil { return } // Never replace an in-progress edit.
            model.filter = .all
            model.query = ""
            if route == .create { openEditor() }
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

    private func openEditor(id: UUID? = nil) {
        searchFocused = false
        model.open(id: id)
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
                Button("最初のスニペットを作る") { openEditor() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("library.createFirst")
            }
        }
        .padding(.vertical, 30)
    }

    private func snippetRow(_ item: SnippetSummary) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { if model.filter != .trash { openEditor(id: item.id) } } label: {
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
                Button("復元", systemImage: "arrow.uturn.backward") { model.restore(item.id) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("restore.\(item.id)")
            } else {
                Button { model.copy(item.id) } label: {
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
                Button("復元", systemImage: "arrow.uturn.backward") { model.restore(item.id) }
                Button("完全に削除", systemImage: "trash", role: .destructive) { permanentDeletion = item }
            } else {
                Button(item.pinned ? "ピン留めを外す" : "ピン留め", systemImage: item.pinned ? "pin.slash" : "pin") { model.pin(item) }
                Button("編集", systemImage: "square.and.pencil") { openEditor(id: item.id) }
                Button("削除", systemImage: "trash", role: .destructive) { model.delete(item.id) }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if model.filter == .trash {
                Button("完全に削除", role: .destructive) { permanentDeletion = item }
            } else {
                Button("削除", role: .destructive) { model.delete(item.id) }
                Button(item.pinned ? "解除" : "ピン留め", systemImage: item.pinned ? "pin.slash" : "pin") { model.pin(item) }.tint(.nibbleAccent)
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
