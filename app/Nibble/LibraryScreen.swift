import SwiftUI
import Tasking
import ScopedAnimation

struct LibraryScreen: View {
    let model: LibraryModel
    let title: String
    let showsDrafts: Bool
    let searchFocused: FocusState<Bool>.Binding
    var actionButtonSide: ActionButtonSide = .right
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var taskOwner = LibraryTaskOwner()
    @State private var permanentDeletion: SnippetSummary?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var library = model
        List {
            if showsDrafts && !model.drafts.isEmpty {
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
                if showsDrafts {
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
                    Section(sectionTitle) {
                        ForEach(model.items) { item in snippetRow(item) }
                    }
                }
                if model.hasMore || model.loading {
                    Section {
                        if model.hasMore {
                            Button("さらに表示") { model.showMore() }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        if model.loading { ProgressView().frame(maxWidth: .infinity) }
                    }
                }
                if model.filter == .trash {
                    Text("自動では消えません。必要な項目を復元できます。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.nibbleCanvas)
        .scrollDismissesKeyboard(.interactively)
        .modifier(LibraryNavigationTitle(title: title, leading: model.filter != .trash))
        .safeAreaInset(edge: .bottom, alignment: actionsAtLeading ? .leading : .trailing, spacing: 0) {
            VStack(alignment: actionsAtLeading ? .leading : .trailing, spacing: 12) {
                notice
                if model.filter != .trash && !searchFocused.wrappedValue {
                    Button { startTask(.open(.new)) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .regular))
                            .frame(width: 56, height: 56)
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
            }
        } message: { Text("この項目と対応する下書きは元に戻せません。") }
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

    private var notice: some View {
        AnimationScope(.easeOut(duration: reduceMotion ? 0 : 0.16), value: model.notice != nil, name: "Library.Notice") {
            if let notice = model.notice {
                HStack(spacing: 16) {
                    Label(notice.message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
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
            if showsDrafts {
                Button("最初のスニペットを作る") { startTask(.open(.new)) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("library.createFirst")
            }
        }
        .padding(.vertical, 30)
    }

    private var actionsAtLeading: Bool {
        (actionButtonSide == .left) == (layoutDirection == .leftToRight)
    }

    private func copyButton(_ item: SnippetSummary) -> some View {
        Button { startTask(.copy(item.id)) } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 16, weight: .regular))
                .frame(width: 32, height: 32)
                .background(Color.nibbleAccent.opacity(0.07), in: .rect(cornerRadius: 10))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(item.displayTitle)をコピー")
        .accessibilityIdentifier("copy.\(item.id)")
    }

    private func snippetRow(_ item: SnippetSummary) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if model.filter != .trash && actionsAtLeading { copyButton(item) }
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
            } else if !actionsAtLeading {
                copyButton(item)
            }
        }
        .padding(.vertical, 4)
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

