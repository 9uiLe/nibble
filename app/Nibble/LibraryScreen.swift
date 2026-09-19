import AppMacros
import SwiftUI
import Tasking
import ScopedAnimation

@Equatable
struct LibraryScreen: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    @SkipEquatable let model: LibraryModel
    let title: String
    let showsFilters: Bool
    var showsSearchPrompt = false
    @SkipEquatable let searchFocused: FocusState<Bool>.Binding
    var actionButtonSide: ActionButtonSide = .right
    @Environment(\.layoutDirection) private var layoutDirection
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
                LibraryNotice(model: model, restore: { startTask(.restore($0)) })
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
                if model.loadingInterrupted {
                    Button { startTask(.refresh) } label: {
                        Label("読み込みを再開", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .accessibilityIdentifier("library.resumeLoading")
                }
                if searchPrompt {
                    if model.loading { loadingRow }
                    ContentUnavailableView("スニペットを検索", systemImage: "magnifyingglass",
                                           description: Text("タイトルや本文の言葉で探せます。"))
                        .accessibilityIdentifier("search.prompt")
                        .listRowSeparator(.hidden)
                } else {
                    if model.loading && !model.contentIsCurrent { loadingRow }
                    if model.contentIsCurrent || model.loading || model.loadingInterrupted {
                        libraryContent.disabled(!model.contentIsCurrent)
                    }
                    if model.contentIsCurrent && (model.hasMore || model.loading) {
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
        .id(model.contentRequest.filter)
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
                                    .foregroundStyle(.primary).lineLimit(2)
                                if !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(draft.preview).font(.subheadline).foregroundStyle(.secondary)
                                        .lineLimit(2)
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
        if model.contentIsCurrent && contentIsEmpty && !model.loading && !model.loadingInterrupted && model.failure == nil {
            emptyState
        } else if model.contentRequest.filter != .drafts {
            Section {
                ForEach(visibleItems) { item in snippetRow(item) }
            } header: {
                if model.contentRequest.filter != .pinned && model.contentRequest.filter != .trash { Text(sectionTitle) }
            }
            if model.contentRequest.filter == .trash {
                Text("自動では消えません。必要な項目を復元できます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var loadingRow: some View {
        ProgressView(showsFilters ? "\(model.filter.title)を読み込み中" : "読み込み中")
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
                } else if failure.recovery == .retryUsage {
                    Button("使用記録を再試行") { startTask(.retryUsage) }
                        .buttonStyle(.bordered).controlSize(.large)
                        .accessibilityIdentifier("library.retryUsage")
                } else {
                    Button("閉じる") { model.dismissFailure() }
                        .buttonStyle(.bordered).controlSize(.large)
                        .accessibilityIdentifier("library.dismissFailure")
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var displaysDrafts: Bool { showsFilters && (model.contentRequest.filter == .all || model.contentRequest.filter == .drafts) }
    private var visibleItems: [SnippetSummary] {
        switch model.contentRequest.filter {
        case .pinned: model.page.pinnedItems
        case .drafts: []
        default: model.items
        }
    }
    private var contentIsEmpty: Bool { visibleItems.isEmpty && (!displaysDrafts || model.drafts.isEmpty) }
    private var showsCreationCTA: Bool {
        showsFilters && (model.filter == .all || model.filter == .drafts)
            && model.contentIsCurrent && contentIsEmpty && !model.loading && !model.loadingInterrupted && model.failure == nil
    }

    private func startTask(_ action: LibraryTaskOwner.Action) {
        if case .open = action { searchFocused.wrappedValue = false }
        taskOwner.startTask(action, on: model)
    }

    private var sectionTitle: String {
        if model.contentRequest.filter == .trash { return "削除した項目" }
        return model.contentRequest.query.isEmpty ? (model.contentRequest.filter == .pinned ? "ピン留めしたスニペット" : "手元のスニペット") : "検索結果"
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

    private func snippetRow(_ item: SnippetSummary) -> some View {
        SnippetRow(item: item, isTrash: model.contentRequest.filter == .trash, actionsAtLeading: actionsAtLeading,
                   unusedSince: model.contentRequest.filter != .trash && item.isDeletionCandidate(at: model.evaluatedAt) ? item.lastUsedAt : nil,
                   perform: { action in
            switch action {
            case .edit: startTask(.open(.snippet(item.id)))
            case .copy: startTask(.copy(item.id))
            case .pin: startTask(.pin(item))
            case .delete: startTask(.delete(item.id))
            case .restore: startTask(.restore(item.id))
            case .permanentlyDelete: permanentDeletion = item
            }
        })
    }
}
