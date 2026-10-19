import AppMacros
import SwiftUI
import Tasking

@MainActor @Equatable
struct WorkspaceEntryView: View {
    private enum Startup {
        case loading
        case ready(WorkspaceModel, WorkspaceRepository)
        case failed(WorkspaceError)
    }
    @State private var startup: Startup = .loading
    @State private var pendingURL: URL?
    @State private var linkMessage: String?
    @State private var tasks = ViewTaskStore()

    var body: some View {
        Group {
            switch startup {
            case .loading:
                ProgressView("文章を開いています")
            case .failed(let error):
                VStack(spacing: 20) {
                    WorkspaceErrorView(error: error)
                    Button("もう一度開く") { startTask(nil) }
                }.padding()
            case .ready(let model, let storage):
                WorkspaceHomeView(model: model, storage: storage, delivery: ClipboardDelivery())
            }
        }
        .task { await load() }
        .onOpenURL { url in startTask(url) }
        .alert("外部からの呼び出し", isPresented: Binding(get: { linkMessage != nil }, set: { if !$0 { linkMessage = nil } })) {
            Button("閉じる", role: .cancel) { linkMessage = nil }
        } message: { Text(linkMessage ?? "") }
    }

    private func load() async {
        do {
            let storage = try WorkspaceRepository()
            let model = WorkspaceModel(storage: storage)
            await model.refresh()
            startup = .ready(model, storage)
            if let pendingURL {
                self.pendingURL = nil
                await open(pendingURL, on: model, storage: storage)
            }
        } catch { startup = .failed(WorkspaceError.normalize(error)) }
    }

    private func open(_ url: URL, on model: WorkspaceModel, storage: any WorkspaceStorage) async {
        guard let link = WorkspaceLink(url) else {
            linkMessage = "このリンクは開けませんでした。nibbleの一覧から文章を探すか、作成してください。"
            return
        }
        guard !model.hasOpenWork else {
            linkMessage = "今の入力を保持しています。作業を閉じてから、リンクをもう一度開いてください。"
            return
        }
        switch link {
        case .library: await model.reload()
        case .create(let title, let body): await model.create(title: title, body: body)
        case .use(let id): await model.use(cardID: id)
        }
    }

    private func startTask(_ url: URL?) {
        tasks.start(id: "workspace.entry", lifetime: .sceneBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            guard let url else { await load(); return }
            switch startup {
            case .ready(let model, let storage): await open(url, on: model, storage: storage)
            case .loading: pendingURL = url
            case .failed: pendingURL = url; await load()
            }
        }
    }
}
