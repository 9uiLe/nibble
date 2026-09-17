import SwiftUI
import Tasking
import ScopedAnimation

struct LibraryScreen: View {
    let model: LibraryModel
    let title: String
    let showsFilters: Bool
    var showsSearchPrompt = false
    let searchFocused: FocusState<Bool>.Binding
    var actionButtonSide: ActionButtonSide = .right
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var taskOwner = LibraryTaskOwner()
    @State private var permanentDeletion: SnippetSummary?

    var body: some View {
        @Bindable var library = model
        VStack(spacing: 0) {
            if showsFilters {
                LibraryFilterBar(selection: $library.filter)
                    .fixedSize(horizontal: false, vertical: true)
            }
            snippetList
        }
        .background(Color.nibbleCanvas)
        .modifier(LibraryNavigationTitle(title: title, leading: model.filter != .trash))
        .safeAreaInset(edge: .bottom, alignment: actionsAtLeading ? .leading : .trailing, spacing: 0) {
            VStack(alignment: actionsAtLeading ? .leading : .trailing, spacing: 12) {
                notice
                if model.filter != .trash && !searchFocused.wrappedValue && !showsCreationCTA {
                    Button { startTask(.open(.new)) } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium))
                            .frame(minWidth: 56, minHeight: 56)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.nibbleAccent)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("新しいスニペット")
                    .accessibilityIdentifier("library.add")
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(item: $library.editor, onDismiss: { startTask(.refresh) }) { draft in
            SnippetEditor(draft: draft, store: model.store)
        }
        .confirmationDialog("完全に削除しますか？", isPresented: Binding(get: { permanentDeletion != nil }, set: { if !$0 { permanentDeletion = nil } }), titleVisibility: .visible) {
            if let item = permanentDeletion {
                Button("完全に削除", role: .destructive) { startTask(.permanentlyDelete(item.id)); permanentDeletion = nil }
                    .accessibilityIdentifier("library.confirmPermanentDelete")
            }
        } message: {
            if let item = permanentDeletion {
                Text("「\(item.displayTitle)」と対応する下書きは元に戻せません。")
            }
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
        .onDisappear {
            taskOwner.endScreen()
            model.clearNotice()
        }
    }

    private var searchPrompt: Bool {
        showsSearchPrompt && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var snippetList: some View {
        List {
            Group {
                if let failure = model.failure { failureSection(failure) }
                if searchPrompt {
                    if model.loading { loadingRow }
                    ContentUnavailableView("スニペットを検索", systemImage: "magnifyingglass",
                                           description: Text("タイトルや本文の言葉で探せます。"))
                        .accessibilityIdentifier("search.prompt")
                        .listRowSeparator(.hidden)
                } else {
                    libraryContent
                    if model.hasMore || model.loading {
                        Section {
                            if model.hasMore {
                                Button { model.showMore() } label: {
                                    Text("さらに表示")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .contentShape(.rect)
                                }
                                    .accessibilityIdentifier("library.loadMore")
                            }
                            if model.loading { loadingRow }
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .id(model.filter)
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.nibbleCanvas)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var libraryContent: some View {
        if displaysDrafts && !model.drafts.isEmpty {
            Section("下書き") {
                ForEach(model.drafts) { draft in
                    Button { startTask(.open(.draft(draft.id))) } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.displayTitle).font(.headline)
                                    .foregroundStyle(.primary).lineLimit(expandedRows ? nil : 2)
                                if !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(draft.preview).font(.subheadline).foregroundStyle(.secondary)
                                        .lineLimit(expandedRows ? nil : 2)
                                }
                                Text(draft.updatedAt, format: .dateTime.month().day().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "square.and.pencil").font(.body) }
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下書き、\(draft.displayTitle)")
                    .accessibilityValue(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Text(draft.updatedAt, format: .dateTime.month().day().hour().minute())
                        : Text("\(draft.preview)、\(draft.updatedAt, format: .dateTime.month().day().hour().minute())"))
                    .accessibilityHint("編集を再開します")
                    .accessibilityIdentifier("draft.\(draft.id)")
                }
                if model.page.hasMoreDrafts {
                    Button { model.filter = .drafts } label: {
                        Label("下書きをすべて見る", systemImage: "arrow.right")
                            .frame(minHeight: 44).contentShape(.rect)
                    }
                        .accessibilityIdentifier("library.allDrafts")
                }
            }
        }
        if contentIsEmpty && !model.loading && model.failure == nil {
            emptyState
        } else if model.filter != .drafts {
            if showsFilters && model.filter == .all {
                if !model.page.pinnedItems.isEmpty {
                    Section("ピン留め済み") {
                        ForEach(model.page.pinnedItems) { item in snippetRow(item) }
                    }
                }
                if !model.page.otherItems.isEmpty {
                    Section("その他") {
                        ForEach(model.page.otherItems) { item in snippetRow(item) }
                    }
                }
            } else {
                Section {
                    ForEach(visibleItems) { item in snippetRow(item) }
                } header: {
                    if model.filter != .pinned && model.filter != .trash { Text(sectionTitle) }
                }
            }
            if model.filter == .trash {
                Text("自動では消えません。必要な項目を復元できます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var loadingRow: some View {
        ProgressView("読み込み中")
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityIdentifier("library.loading")
    }

    private func failureSection(_ failure: LibraryModel.Failure) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(failure.title, systemImage: "exclamationmark.circle")
                    .font(.headline).foregroundStyle(.primary)
                    .accessibilityIdentifier("library.error")
                Text(failure.message).font(.callout).foregroundStyle(.primary)
                if failure.recovery == .reload {
                    Button("一覧を再読み込み") { startTask(.reload) }
                        .buttonStyle(.bordered).controlSize(.large)
                        .accessibilityIdentifier("library.reload")
                } else {
                    Button("閉じる") { model.dismissFailure() }
                        .buttonStyle(.bordered).controlSize(.large)
                        .accessibilityIdentifier("library.dismissFailure")
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var displaysDrafts: Bool { showsFilters && (model.filter == .all || model.filter == .drafts) }
    private var expandedRows: Bool { dynamicTypeSize.isAccessibilitySize }
    private var visibleItems: [SnippetSummary] {
        switch model.filter {
        case .pinned: model.page.pinnedItems
        case .drafts: []
        default: model.items
        }
    }
    private var contentIsEmpty: Bool { visibleItems.isEmpty && (!displaysDrafts || model.drafts.isEmpty) }
    private var showsCreationCTA: Bool {
        showsFilters && (model.filter == .all || model.filter == .drafts)
            && contentIsEmpty && !model.loading && model.failure == nil
    }

    private var notice: some View {
        AnimationScope(.easeOut(duration: reduceMotion ? 0 : 0.16), value: model.notice != nil, name: "Library.Notice") {
            if let notice = model.notice {
                let layout = expandedRows ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 16))
                layout {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(notice.message, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                        if let subject = notice.subject {
                            Text(subject).font(.subheadline).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(notice.announcement)
                    .accessibilityIdentifier("library.notice")
                    if let id = notice.undoID {
                        Button { startTask(.restore(id)) } label: {
                            Text("元に戻す")
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44).contentShape(.rect)
                        }
                        .buttonStyle(.borderless)
                            .accessibilityIdentifier("library.undo")
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(.regularMaterial, in: .rect(cornerRadius: 20))
                .transition(.opacity)
            }
        }
    }

    private func startTask(_ action: LibraryTaskOwner.Action) {
        if case .open = action { searchFocused.wrappedValue = false }
        taskOwner.startTask(action, on: model)
    }

    private var sectionTitle: String {
        if model.filter == .trash { return "削除した項目" }
        return model.query.isEmpty ? (model.filter == .pinned ? "ピン留めしたスニペット" : "手元のスニペット") : "検索結果"
    }

    private var emptyContent: (title: String, symbol: String, message: String) {
        if !model.query.isEmpty {
            return ("見つかりませんでした", "magnifyingglass", "別の言葉や、短い語句で探してみてください。")
        }
        if model.filter == .trash {
            return ("削除した項目はありません", "trash", "削除したスニペットはここから復元できます。")
        }
        if model.filter == .drafts {
            return ("下書きはありません", "square.and.pencil", "編集中の内容を閉じると、ここから再開できます。")
        }
        if model.filter == .pinned {
            return ("ピン留めした項目はありません", "pin", "項目の「その他」からピン留めできます。")
        }
        return ("言葉を、すぐ手元に。", "text.quote", "よく使う言葉を保存して、\n次からはワンタップでコピー。")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyContent.title, systemImage: emptyContent.symbol)
        } description: {
            Text(emptyContent.message)
        } actions: {
            if showsCreationCTA {
                Button("新しいスニペットを作る") { startTask(.open(.new)) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("library.createFirst")
                    .keyboardShortcut("n", modifiers: .command)
            } else if showsFilters && model.filter == .pinned {
                Button("すべてを見る") { model.filter = .all }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("library.showAll")
            }
        }
        .padding(.vertical, 30)
        .listRowSeparator(.hidden)
    }

    private var actionsAtLeading: Bool {
        (actionButtonSide == .left) == (layoutDirection == .leftToRight)
    }

    private func copyButton(_ item: SnippetSummary) -> some View {
        Button { startTask(.copy(item.id)) } label: {
            Image(systemName: "doc.on.doc")
                .font(.body)
                .padding(8)
                .background(Color.nibbleAccent.opacity(0.07), in: .rect(cornerRadius: 10))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(item.displayTitle)をコピー")
        .accessibilityIdentifier("copy.\(item.id)")
    }

    private func rowActions(_ item: SnippetSummary) -> some View {
        HStack(spacing: 0) {
            if model.filter == .trash {
                Button { startTask(.restore(item.id)) } label: {
                    Image(systemName: "arrow.uturn.backward").font(.body)
                        .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(item.displayTitle)を復元")
                    .accessibilityIdentifier("restore.\(item.id)")
            } else { copyButton(item) }
            Menu { rowMenu(item) } label: {
                Image(systemName: "ellipsis").font(.body)
                    .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("\(item.displayTitle)のその他の操作")
            .accessibilityIdentifier("more.\(item.id)")
        }
    }

    private func rowLabel(_ item: SnippetSummary) -> some View {
        SnippetRowContent(title: item.title, preview: item.preview, pinned: item.pinned, expanded: expandedRows)
    }

    @ViewBuilder private func rowContent(_ item: SnippetSummary) -> some View {
        if model.filter == .trash {
            rowLabel(item)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.displayTitle)
                .accessibilityIdentifier("snippet.\(item.id)")
        } else {
            Button { startTask(.open(.snippet(item.id))) } label: { rowLabel(item) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("snippet.\(item.id)")
                .accessibilityLabel(item.pinned ? "ピン留め、\(item.displayTitle)" : item.displayTitle)
                .accessibilityHint("編集します")
        }
    }

    private func snippetRow(_ item: SnippetSummary) -> some View {
        Group {
            if expandedRows {
                VStack(alignment: .leading, spacing: 8) {
                    rowContent(item)
                    rowActions(item).frame(maxWidth: .infinity, alignment: actionsAtLeading ? .leading : .trailing)
                }
            } else {
                HStack(spacing: 8) {
                    if actionsAtLeading { rowActions(item) }
                    rowContent(item)
                    if !actionsAtLeading { rowActions(item) }
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu { rowMenu(item) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if model.filter == .trash {
                Button("完全に削除", role: .destructive) { permanentDeletion = item }
            } else {
                Button("削除", role: .destructive) { startTask(.delete(item.id)) }
                Button(item.pinned ? "解除" : "ピン留め", systemImage: item.pinned ? "pin.slash" : "pin") { startTask(.pin(item)) }.tint(.nibbleAccent)
            }
        }
    }

    @ViewBuilder private func rowMenu(_ item: SnippetSummary) -> some View {
        if model.filter == .trash {
            Button("復元", systemImage: "arrow.uturn.backward") { startTask(.restore(item.id)) }
            Button("完全に削除", systemImage: "trash", role: .destructive) { permanentDeletion = item }
                .accessibilityIdentifier("permanentlyDelete.\(item.id)")
        } else {
            Button("編集", systemImage: "square.and.pencil") { startTask(.open(.snippet(item.id))) }
            Button(item.pinned ? "ピン留めを外す" : "ピン留め", systemImage: item.pinned ? "pin.slash" : "pin") { startTask(.pin(item)) }
            Button("削除", systemImage: "trash", role: .destructive) { startTask(.delete(item.id)) }
                .accessibilityIdentifier("delete.\(item.id)")
        }
    }
}

/// These controls change the contents of one library, while the tab bar changes screens.
private struct LibraryFilterBar: View {
    @Binding var selection: LibraryFilter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach([LibraryFilter.all, .pinned, .drafts], id: \.self) { filter in
                        Button { selection = filter } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark").opacity(selection == filter ? 1 : 0)
                                    .accessibilityHidden(true)
                                Text(filter.title)
                            }
                            .font(.subheadline.weight(.semibold))
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .foregroundStyle(selection == filter ? Color.nibbleAccent : Color.primary)
                            .background(selection == filter ? Color.nibbleAccent.opacity(0.14) : Color.clear,
                                        in: .rect(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(selection == filter ? Color.nibbleAccent : Color.secondary.opacity(0.4))
                            }
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == filter ? [.isSelected] : [])
                        .accessibilityIdentifier("library.filter.\(filter.rawValue)")
                        .id(filter)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .background(Color.nibbleCanvas)
            .overlay(alignment: .bottom) { Divider() }
            .onChange(of: selection) { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: dynamicTypeSize) { proxy.scrollTo(selection, anchor: .center) }
        }
    }
}
