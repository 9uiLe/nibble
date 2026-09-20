import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Tasking

@MainActor
final class ShareViewController: UIViewController {
    private let store = SnippetStorage.sharedContainer()
    private let tasks = ViewTaskStore()
    private static let load: ActionID = "share.load"

    override func viewDidLoad() {
        super.viewDidLoad()
        NibbleInterface.apply(to: &traitOverrides)
        view.backgroundColor = .systemBackground
        startTask()
    }

    private func startTask() {
        tasks.start(id: Self.load, lifetime: .screenBound, policy: .ignoreNew) { [weak self] _ in
            await self?.presentEditor()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        tasks.cancel(lifetime: .screenBound)
    }

    private func presentEditor() async {
        do {
            try Task.checkCancellation()
            let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) else {
                throw ShareError.unsupported
            }
            let body = try await Self.read(provider)
            try Task.checkCancellation()
            try SnippetText.validate(title: "", body: body)
            let draft = try await store.beginDraft(body: body)
            // Persisted shared text remains recoverable, but a departed host must not present UI.
            try Task.checkCancellation()
            let host = UIHostingController(rootView: SnippetEditor(draft: draft, store: store) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }.modifier(NibbleInterface()))
            NibbleInterface.apply(to: &host.traitOverrides)
            addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            host.didMove(toParent: self)
        } catch is CancellationError {
            extensionContext?.cancelRequest(withError: CancellationError())
        } catch {
            guard !Task.isCancelled else {
                extensionContext?.cancelRequest(withError: CancellationError())
                return
            }
            let alert = UIAlertController(title: "取り込めませんでした", message: Self.failureMessage(error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "閉じる", style: .cancel) { [weak self] _ in
                self?.extensionContext?.cancelRequest(withError: ShareError.unsupported)
            })
            present(alert, animated: true)
        }
    }

    private static func failureMessage(_ error: Error) -> String {
        switch error {
        case ShareError.unsupported:
            "文章またはURLを選んで共有してください。「閉じる」で共有元のアプリに戻れます。"
        case StoreError.empty:
            "共有する文章が空です。共有元のアプリで、空白や改行以外の文字を選んで共有してください。"
        case StoreError.tooLarge:
            "共有する文章が長すぎます。共有元のアプリで短くしてから、もう一度共有してください。本文の上限はUTF-8で1 MB（1,000,000バイト）です。"
        case StoreError.newerVersion:
            "nibbleを最新バージョンに更新してから、もう一度共有してください。"
        case is StoreError:
            "共有した内容を下書きに保存できませんでした。「閉じる」で共有元のアプリに戻り、もう一度共有してください。"
        default:
            "共有元のアプリから内容を読み込めませんでした。「閉じる」で戻り、もう一度共有してください。"
        }
    }

    private static func read(_ provider: NSItemProvider) async throws -> String {
        let type = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) ? UTType.plainText.identifier : UTType.url.identifier
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else if let text = item as? String { continuation.resume(returning: text) }
                else if let url = item as? URL { continuation.resume(returning: url.absoluteString) }
                else if let data = item as? Data, let text = String(data: data, encoding: .utf8) { continuation.resume(returning: text) }
                else { continuation.resume(throwing: ShareError.unsupported) }
            }
        }
    }
}

private enum ShareError: Error, LocalizedError {
    case unsupported
    var errorDescription: String? { "文章またはURLを選んで共有してください。" }
}
