import AppMacros
import SwiftUI
import Tasking

@MainActor @Equatable
struct WorkspaceTrashView: View {
    private enum Action { case restore(TextCard), more, retry }
    private let inputRevision = UUID()
    @SkipEquatable let storage: any WorkspaceStorage
    @State private var model: WorkspaceModel
    @State private var search = ""
    @State private var tasks = ViewTaskStore()

    init(storage: any WorkspaceStorage) {
        self.storage = storage
        _model = State(initialValue: WorkspaceModel(storage: storage))
    }

    var body: some View {
        List {
            Section {
                Text("ここにある文章は通常の一覧とキーボードには出ません。作業中の入力は別に残ります。必要な文章を戻してください。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let error = model.error {
                WorkspaceErrorView(error: error)
                Button("もう一度読み込む") { startTask(.retry) }
                    .accessibilityIdentifier("workspace.trash.retry")
            }
            ForEach(model.cards) { card in
                VStack(alignment: .leading, spacing: 8) {
                    WorkspaceCardRow(card: card)
                        .accessibilityIdentifier("workspace.trashed.\(card.id.uuidString)")
                    Button("文章を戻す") { startTask(.restore(card)) }
                        .accessibilityIdentifier("workspace.restore.\(card.id.uuidString)")
                }
            }
            if model.loading { ProgressView("読み込んでいます") }
            if model.cards.isEmpty && !model.loading && model.error == nil { Text("ごみ箱は空です") }
            if model.hasMore {
                Button("続きを読み込む") { startTask(.more) }
            }
        }
        .navigationTitle("ごみ箱")
        .searchable(text: $search, prompt: "名前や本文から探す")
        .task(id: search) { await model.refresh(search: search, trash: true) }
        .safeAreaInset(edge: .bottom) {
            if let notice = model.notice { WorkspaceNoticeView(model: model, notice: notice) }
        }
        .onDisappear { tasks.cancel(lifetime: .screenBound) }
    }

    private func startTask(_ action: Action) {
        tasks.start(id: "workspace.trash.action", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            switch action {
            case .restore(let card): await model.restore(card)
            case .more: await model.loadMore()
            case .retry: await model.refresh(search: search, trash: true)
            }
        }
    }
}
