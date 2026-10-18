import SwiftUI
import Tasking
import UIKit

@MainActor
final class ShareViewController: UIViewController {
    private let store = SnippetStore(location: SnippetLocation.database)
    private let tasks = ViewTaskStore()
    private var started = false
    private var visible = false
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        NibbleInterface.apply(to: &traitOverrides)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        startTask()
    }
    override func viewDidDisappear(_ animated: Bool) {
        visible = false
        tasks.cancel(lifetime: .screenBound)
        super.viewDidDisappear(animated)
    }
    private func startTask() {
        guard !started else { return }
        started = true
        tasks.start(id: "share.read", lifetime: .screenBound, policy: .ignoreNew) { [weak self] _ in
            await self?.receiveSharedContent()
        }
    }
    private func receiveSharedContent() async {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        do {
            let draft = try await SharedDraftLoader(store: store).load(from: items.flatMap { $0.attachments ?? [] })
            guard visible, !Task.isCancelled else { return }
            let content = SnippetEditor(draft: draft, store: store, proIsActive: ProAccess.isActive, complete: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }).modifier(NibbleInterface())
            let host = UIHostingController(rootView: content)
            NibbleInterface.apply(to: &host.traitOverrides)
            addChild(host)
            view.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            host.didMove(toParent: self)
        } catch is CancellationError { return }
        catch {
            guard visible, !Task.isCancelled else { return }
            let alert = UIAlertController(title: "取り込めませんでした", message: ShareFailureMessage.text(for: error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "閉じる", style: .cancel) { [weak self] _ in
                self?.extensionContext?.cancelRequest(withError: ShareError.unsupported)
            })
            present(alert, animated: true)
        }
    }
}
