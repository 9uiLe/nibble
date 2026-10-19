import AppMacros
import SwiftUI
import Tasking

@MainActor @Equatable
struct WorkspaceHomeView: View {
    private enum Action {
        case create, more, retry
        case use(TextCard), edit(TextCard), pin(TextCard), trash(TextCard), restore(TextCard), resume(WorkDraft)
    }
    private struct Search: Hashable { let query: String; let pinned: Bool }
    private let inputRevision = UUID()
    @SkipEquatable let model: WorkspaceModel
    @SkipEquatable let storage: any WorkspaceStorage
    @SkipEquatable let delivery: any TextDelivery
    @State private var search = ""
    @State private var pinned = false
    @State private var settings = false
    @State private var deleting: TextCard?
    @State private var tasks = ViewTaskStore()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("名前や本文から探す", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("workspace.search")
                Picker("表示する文章", selection: $pinned) {
                    Text("すべて").tag(false)
                    Text("ピン留め").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .accessibilityIdentifier("workspace.filter")
                List {
                    if let error = model.error {
                        Section {
                            WorkspaceErrorView(error: error)
                            Button("もう一度読み込む") { startTask(.retry) }
                                .accessibilityIdentifier("workspace.retry")
                        }
                    }
                    if !model.drafts.isEmpty {
                        Section("作業中") {
                            ForEach(Array(model.drafts.prefix(2))) { draft in
                                Button { startTask(.resume(draft)) } label: {
                                    Label(WorkspacePresentation.draftTitle(draft), systemImage: "pencil.and.outline")
                                        .lineLimit(2)
                                }
                                .accessibilityIdentifier("workspace.draft.\(draft.id.uuidString)")
                            }
                            NavigationLink("作業中をすべて見る（\(model.drafts.count)）") {
                                WorkspaceDraftsView(model: model)
                            }
                        }
                    }
                    Section {
                        ForEach(model.cards) { card in
                            HStack(alignment: .top) {
                                Button { startTask(.use(card)) } label: { WorkspaceCardRow(card: card) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("workspace.card.\(card.id.uuidString)")
                                Menu {
                                    Button("編集", systemImage: "pencil") { startTask(.edit(card)) }
                                    Button(card.pinned ? "ピン留めを外す" : "ピン留め", systemImage: "pin") { startTask(.pin(card)) }
                                    Button("ごみ箱へ移す", systemImage: "trash", role: .destructive) { deleting = card }
                                } label: {
                                    Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                                }
                                .accessibilityLabel("\(WorkspacePresentation.title(card))の管理")
                                .accessibilityIdentifier("workspace.manage.\(card.id.uuidString)")
                            }
                        }
                        if model.hasMore {
                            Button("続きを読み込む") { startTask(.more) }
                                .accessibilityIdentifier("workspace.more")
                        }
                        if model.loading { ProgressView("読み込んでいます") }
                        if model.cards.isEmpty && !model.loading && model.error == nil {
                            ContentUnavailableView(search.isEmpty ? "使う文章を用意しましょう" : "一致する文章がありません",
                                                   systemImage: search.isEmpty ? "text.badge.plus" : "magnifyingglass",
                                                   description: Text(search.isEmpty ? "作成するか、他のアプリの共有からnibbleへ取り込みます。" : "名前や本文の一部で探してください。"))
                        }
                    } header: { Text("文章 \(model.total)件") }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await model.refresh(search: search, pinned: pinned) }
            }
            .navigationTitle("nibble")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("使い方と管理", systemImage: "gearshape") { settings = true }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("workspace.settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("作成", systemImage: "plus") { startTask(.create) }
                        .accessibilityIdentifier("workspace.create")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let notice = model.notice {
                    WorkspaceNoticeView(model: model, notice: notice)
                }
            }
            .sheet(item: Binding(get: { model.route }, set: { model.route = $0 })) { route in
                switch route {
                case .editor(let editor):
                    WorkspaceEditorView(model: editor) { saved in await model.finished(saved: saved) }
                case .use(let use):
                    WorkspaceUseView(model: use, delivery: delivery) { await model.finished() }
                }
            }
            .sheet(isPresented: $settings, onDismiss: { startTask(.retry) }) {
                WorkspaceSettingsView(storage: storage)
            }
            .confirmationDialog("「\(deleting.map(WorkspacePresentation.title) ?? "選んだ文章")」をごみ箱へ移しますか？ 後から戻せます。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                if let card = deleting {
                    Button("ごみ箱へ移す", role: .destructive) { startTask(.trash(card)); deleting = nil }
                }
            }
            .task(id: Search(query: search, pinned: pinned)) { await model.refresh(search: search, pinned: pinned) }
            .onChange(of: phase) { _, phase in
                if phase == .active { startTask(.retry) }
            }
            .onDisappear { tasks.cancel(lifetime: .screenBound) }
        }
    }

    private func startTask(_ action: Action) {
        tasks.start(id: "workspace.home.action", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            switch action {
            case .create: await model.create()
            case .more: await model.loadMore()
            case .retry: await model.refresh(search: search, pinned: pinned)
            case .use(let card): await model.use(card)
            case .edit(let card): await model.edit(card)
            case .pin(let card): await model.pin(card)
            case .trash(let card): await model.trash(card)
            case .restore(let card): await model.restore(card)
            case .resume(let draft): await model.resume(draft)
            }
        }
    }
}
