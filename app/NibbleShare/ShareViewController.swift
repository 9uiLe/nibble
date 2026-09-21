import UIKit
import SwiftUI
import Tasking

@MainActor
final class ShareViewController: UIViewController {
    private let store = SnippetStore(location: SnippetLocation.database)
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
            let draft = try await SharedDraftLoader(store: store).load(from: providers)
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
            let alert = UIAlertController(title: "取り込めませんでした", message: ShareFailureMessage.text(for: error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "閉じる", style: .cancel) { [weak self] _ in
                self?.extensionContext?.cancelRequest(withError: ShareError.unsupported)
            })
            present(alert, animated: true)
        }
    }
}
