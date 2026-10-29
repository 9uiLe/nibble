import AppMacros
import SwiftUI
import Tasking

@MainActor @Equatable
struct WorkspaceHomeView: View {
    private enum Action { case create, more, retry, use(TextCard), copy(TextCard) }
    private let inputRevision = UUID()
    @SkipEquatable let model: WorkspaceModel
    @SkipEquatable let storage: any WorkspaceStorage
    @SkipEquatable let delivery: any TextDelivery
    @State private var search = ""
    @State private var tasks = ViewTaskStore()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("nibble")
                    .font(.largeTitle.bold())
                    .tracking(-0.8)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                WorkspaceSearchField(search: $search)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let error = model.error {
                            WorkspaceErrorView(error: error)
                            Button("もう一度読み込む") { startTask(.retry) }
                                .accessibilityIdentifier("workspace.retry")
                        }
                        ForEach(model.cards) { card in
                            HStack(spacing: 16) {
                                Button { startTask(.use(card)) } label: { WorkspaceCardRow(card: card) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("workspace.card.\(card.id.uuidString)")
                                Button { startTask(.copy(card)) } label: {
                                    Label("\(WorkspacePresentation.title(card))をコピー", systemImage: "doc.on.doc")
                                        .labelStyle(.iconOnly)
                                        .font(.system(size: 16))
                                        .frame(width: 44, height: 44)
                                        .background(WorkspaceStyle.subtle, in: Circle())
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("workspace.copy.\(card.id.uuidString)")
                            }
                            .padding(.top, card.id == model.cards.first?.id ? 0 : 20)
                            .padding(.bottom, 20)
                            .overlay(alignment: .bottom) { Rectangle().fill(WorkspaceStyle.divider).frame(height: 1) }
                        }
                        if model.hasMore {
                            Button("続きを読み込む") { startTask(.more) }
                                .padding(.vertical, 20)
                                .accessibilityIdentifier("workspace.more")
                        }
                        if model.loading { ProgressView("読み込んでいます") }
                        if model.cards.isEmpty && !model.loading && model.error == nil {
                            ContentUnavailableView(search.isEmpty ? "プロンプトがありません" : "一致するプロンプトがありません",
                                                   systemImage: search.isEmpty ? "text.badge.plus" : "magnifyingglass")
                        }
                    }
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await model.refresh(search: search) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .ignoresSafeArea(edges: .bottom)
            .background(Color(uiColor: .systemBackground))
            .foregroundStyle(WorkspaceStyle.text)
            .overlay(alignment: .bottomTrailing) {
                Button { startTask(.create) } label: {
                    Label("新規プロンプトを作成", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Color.primary.opacity(0.9)).interactive(), in: .circle)
                .padding(.trailing, 24)
                .padding(.bottom, 2)
                .accessibilityIdentifier("workspace.create")
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let notice = model.notice { WorkspaceNoticeView(model: model, notice: notice) }
            }
            .navigationDestination(isPresented: Binding<Bool>(get: {
                if case .prompt = model.route { return true }
                return false
            }, set: { presented in if !presented { model.route = nil } })) {
                if case .prompt(let prompt) = model.route {
                    PromptDetailView(model: prompt, delivery: delivery) { await model.finished() } onDeleted: { deleted in
                        await model.finishedDeletingPrompt(deleted)
                    }
                }
            }
            .fullScreenCover(item: Binding<WorkspaceModel.Route?>(get: {
                if case .prompt = model.route { return nil }
                return model.route
            }, set: { route in
                if case .prompt = model.route { return }
                model.route = route
            })) { route in
                switch route {
                case .editor(let editor):
                    PromptEditorView(model: editor) { saved in await model.finished(saved: saved) }
                case .use(let use):
                    WorkspaceUseView(model: use, delivery: delivery) { await model.finished() }
                case .prompt: EmptyView()
                }
            }
            .task(id: search) { await model.refresh(search: search) }
            .onChange(of: phase) { _, phase in
                if phase == .active { startTask(.retry) }
            }
            .onDisappear { tasks.cancel(lifetime: .screenBound) }
        }
        .tint(.primary)
    }

    private func startTask(_ action: Action) {
        let id: ActionID
        switch action {
        case .more, .retry: id = "workspace.home.read"
        default: id = "workspace.home.action"
        }
        tasks.start(id: id, lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            switch action {
            case .create: await model.create()
            case .more: await model.loadMore()
            case .retry: await model.refresh(search: search)
            case .use(let card): await model.openPrompt(card)
            case .copy(let card): await model.copy(card, using: delivery)
            }
        }
    }
}
