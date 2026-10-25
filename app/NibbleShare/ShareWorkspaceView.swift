import AppMacros
import SwiftUI

@MainActor @Equatable
struct ShareWorkspaceView: View {
    private enum Loading {
        case loading
        case ready(DraftSessionModel)
        case failed(String)
    }
    private let inputRevision = UUID()
    @SkipEquatable let context: NSExtensionContext
    @State private var state: Loading = .loading

    var body: some View {
        Group {
            switch state {
            case .loading: ProgressView("共有された文章を開いています")
            case .ready(let editor):
                WorkspaceEditorView(model: editor) { saved in
                    context.completeRequest(returningItems: [])
                }
            case .failed(let message):
                VStack(spacing: 20) {
                    Text(message).accessibilityIdentifier("workspace.share.error")
                    Button("取り込みをやめる") {
                        context.cancelRequest(withError: NSError(domain: "nibble.share", code: 1))
                    }
                }.padding()
            }
        }
        .task {
            do {
                let providers = (context.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
                let body = try await IncomingTextLoader.load(providers)
                try Task.checkCancellation()
                let storage = try WorkspaceRepository()
                let draft = try await storage.beginDraft(title: "", body: body)
                try Task.checkCancellation()
                state = .ready(DraftSessionModel(draft: draft, storage: storage))
            } catch is CancellationError {
                return
            } catch IncomingTextError.unsupported {
                state = .failed("この形式は取り込めません。文章を選択して共有するか、nibble本体の作成画面へペーストしてください。保存済みの文章は変わっていません。")
            } catch IncomingTextError.tooLarge {
                state = .failed("この文章は大きすぎて一度に取り込めません。必要な範囲を選んで共有してください。保存済みの文章は変わっていません。")
            } catch IncomingTextError.multipleItems {
                state = .failed("複数の項目が共有されています。取り込みたい文章を一つ選んで、もう一度共有してください。今回は保存していません。")
            } catch {
                state = .failed(WorkspacePresentation.error(WorkspaceError.normalize(error)))
            }
        }
    }
}
