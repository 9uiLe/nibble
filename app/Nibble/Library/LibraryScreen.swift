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
    @Environment(\.scenePhase) private var scenePhase
    @State private var taskOwner = LibraryTaskOwner()
    @State private var permanentDeletion: SnippetSummary?

    var body: some View {
        @Bindable var library = model
        VStack(spacing: 0) {
            if model.filter != .trash { libraryHeading }
            if showsFilters {
                LibraryFilterBar(selection: $library.filter, counts: model.snapshot?.page.counts)
                    .fixedSize(horizontal: false, vertical: true)
            }
            snippetList
        }
        .background(Color.nibbleCanvas)
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
        .toolbar(model.filter == .trash ? .visible : .hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            VStack(alignment: .trailing, spacing: 12) {
                if model.filter == .trash {
                    LibraryNotice(model: model, restore: { startTask(.undoNotice($0)) })
                }
                if model.filter != .trash && !searchFocused.wrappedValue && !showsCreationCTA {
                    Button { startTask(.open(.new)) } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium))
                            .frame(width: 50, height: 50)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.nibbleCanvas)
                    .background(Color.nibbleAccent, in: .circle)
                    .shadow(color: Color.nibbleAccent.opacity(0.15), radius: 7, y: 4)
                    .accessibilityLabel("新しく作る")
                    .accessibilityIdentifier("library.add")
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
        }
        .confirmationDialog("完全に削除しますか？", isPresented: Binding(get: { permanentDeletion != nil }, set: { if !$0 { permanentDeletion = nil } }), titleVisibility: .visible) {
            if let item = permanentDeletion {
                Button("完全に削除", role: .destructive) { startTask(.permanentlyDelete(item.id)); permanentDeletion = nil }
                    .accessibilityIdentifier("library.confirmPermanentDelete")
            }
        } message: {
            if let item = permanentDeletion {
                Text("「\(item.displayTitle)」と、この項目の下書きを完全に削除します。元に戻せません。")
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
            else if scenePhase == .background { taskOwner.endScreen() }
        }
        .onDisappear {
            taskOwner.endScreen()
        }
    }

    private var searchPrompt: Bool {
        showsSearchPrompt && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var libraryHeading: some View {
        ScreenHeading(title: title, subTitle: subTitle)
    }

    private var subTitle: String {
        if showsFilters, let counts = model.snapshot?.page.counts {
            return "保存した項目 \(counts.saved)件"
        }
        return showsFilters ? "保存した文章やURL" : "タイトルや本文の言葉で探す"
    }

    private var snippetList: some View {
        List {
            Group {
                if let failure = model.failure { failureSection(failure) }
                if model.loadingInterrupted {
                    Button { startTask(.refresh) } label: {
                        Label("読み込みを再開", systemImage: "arrow.clockwise")
                            .font(.nibbleTitle)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .accessibilityIdentifier("library.resumeLoading")
                }
                if searchPrompt {
                    if model.loading { loadingRow }
                    ContentUnavailableView {
                        Label {
                            Text("保存した項目を検索").font(.nibbleTitle)
                        } icon: {
                            Image(systemName: "magnifyingglass")
                        }
                    } description: {
                        Text("タイトルや本文の言葉で探せます。")
                            .font(.nibbleBody)
                    }
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
                                        .font(.nibbleTitle)
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
        if displaysDrafts && model.contentRequest.filter == .all, let draft = model.drafts.first {
            draftResume(draft)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 15, leading: 22, bottom: 4, trailing: 22))
        } else if displaysDrafts && !model.drafts.isEmpty {
            Section {
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
            } header: {
                Text("下書き").font(.caption2.weight(.semibold))
            }
        }
        if model.contentIsCurrent && contentIsEmpty && !model.loading && !model.loadingInterrupted && model.failure == nil {
            emptyState
        } else if model.contentRequest.filter != .drafts {
            Section {
                ForEach(model.items) { item in snippetRow(item) }
            } header: {
                if model.contentRequest.filter != .trash && !model.items.isEmpty {
                    HStack {
                        Text(sectionTitle).fontWeight(.semibold)
                        Spacer()
                        Label("使用回数順", systemImage: "arrow.down")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.vertical, 6)
                }
            }
            if model.contentRequest.filter == .trash {
                Text("削除した項目は自動で消えません。復元すると、一覧からまた使えます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func draftResume(_ draft: DraftSummary) -> some View {
        HStack(spacing: 4) {
            Button { startTask(.open(.draft(draft.id))) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.pencil").font(.callout)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("下書きを再開").font(.footnote.weight(.medium))
                        Text(draft.displayTitle).font(.caption2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !model.page.hasMoreDrafts {
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下書きを再開、\(draft.displayTitle)")
            .accessibilityIdentifier("draft.\(draft.id)")
            if model.page.hasMoreDrafts {
                Button { model.filter = .drafts } label: {
                    Text("ほか\(model.page.counts.drafts - 1)件")
                        .font(.caption2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下書きをすべて見る、\(model.page.counts.drafts)件")
                .accessibilityIdentifier("library.allDrafts")
            }
        }
        .foregroundStyle(Color.nibbleAccent)
        .padding(.horizontal, 12)
        .background(Color.nibbleSoft, in: .rect(cornerRadius: 12))
    }

    private var loadingRow: some View {
        ProgressView {
            Text(showsFilters ? "\(model.filter.title)を読み込み中" : "読み込み中")
                .font(.nibbleBody)
        }
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
                        .font(.nibbleTitle)
                        .buttonStyle(.bordered).controlSize(.large)
                        .accessibilityIdentifier("library.reload")
                } else if failure.recovery == .retryUsage {
                    Button("回数と日時を記録し直す") { startTask(.retryUsage) }
                        .font(.nibbleTitle)
                        .buttonStyle(.bordered).controlSize(.large)
                        .accessibilityIdentifier("library.retryUsage")
                } else if case .retryRestore(let id) = failure.recovery {
                    Button("もう一度復元する") { startTask(.restore(id)) }
                        .font(.nibbleTitle)
                        .buttonStyle(.bordered).controlSize(.large)
                        .disabled(model.restoringIDs.contains(id))
                        .accessibilityIdentifier("library.retryRestore")
                } else {
                    Button("閉じる") { model.dismissFailure() }
                        .font(.nibbleTitle)
                        .buttonStyle(.bordered).controlSize(.large)
                        .accessibilityIdentifier("library.dismissFailure")
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var displaysDrafts: Bool { showsFilters && (model.contentRequest.filter == .all || model.contentRequest.filter == .drafts) }
    private var contentIsEmpty: Bool { model.items.isEmpty && (!displaysDrafts || model.drafts.isEmpty) }
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
        return model.contentRequest.query.isEmpty ? (model.contentRequest.filter == .pinned ? "ピン留めした項目" : "保存した項目") : "検索結果"
    }

    private var emptyContent: (title: String, symbol: String, message: String) {
        if !model.query.isEmpty {
            return ("見つかりませんでした", "magnifyingglass", "別の言葉や、短い言葉で検索してください。")
        }
        if model.filter == .trash {
            return ("削除した項目はありません", "trash", "削除した項目はここに表示されます。復元すると、一覧からまた使えます。")
        }
        if model.filter == .drafts {
            return ("下書きはありません", "square.and.pencil", "編集画面で「閉じる」を押すと、入力した内容が下書きに残ります。ここから編集を再開できます。")
        }
        if model.filter == .pinned {
            return ("ピン留めした項目はありません", "pin", "項目の「その他」からピン留めできます。")
        }
        return ("保存した項目はありません", "text.quote", "よく使う文章やURLを保存すると、\nいつでもコピーして使えます。")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text(emptyContent.title).font(.nibbleTitle)
            } icon: {
                Image(systemName: emptyContent.symbol)
            }
        } description: {
            Text(emptyContent.message)
                .font(.nibbleBody)
        } actions: {
            if showsCreationCTA {
                Button("新しく作る") { startTask(.open(.new)) }
                    .font(.nibbleTitle)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("library.createFirst")
                    .keyboardShortcut("n", modifiers: .command)
            } else if showsFilters && model.filter == .pinned {
                Button("すべてを見る") { model.filter = .all }
                    .font(.nibbleTitle)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("library.showAll")
            }
        }
        .padding(.vertical, 30)
        .listRowSeparator(.hidden)
    }

    private func snippetRow(_ item: SnippetSummary) -> some View {
        SnippetRow(item: item, isTrash: model.contentRequest.filter == .trash,
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
