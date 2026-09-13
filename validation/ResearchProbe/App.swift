// Research-only app. All data in this app is disposable test data.
import UIKit
import Foundation
import AppIntents

@main @MainActor final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ProbeShortcuts.updateAppShortcutParameters()
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = ProbeScene.self
        return configuration
    }
}

@MainActor final class ProbeScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var cover: UIView?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UINavigationController(rootViewController: ProbeController())
        window.makeKeyAndVisible(); self.window = window
        if let url = options.urlContexts.first?.url { open(url) }
    }
    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        if let url = contexts.first?.url { open(url) }
    }
    func open(_ url: URL) {
        guard let nav = window?.rootViewController as? UINavigationController,
              let list = nav.viewControllers.first as? ProbeController else { return }
        list.loadViewIfNeeded()
        switch ProbeRoute(url) {
        case .list: nav.popToRootViewController(animated: false)
        case .create: nav.popToRootViewController(animated: false); list.edit(nil)
        case .item(let id):
            nav.popToRootViewController(animated: false)
            if let value = list.values.first(where: { $0.id == id }) { list.edit(value) }
            else { list.notice("項目が見つかりません") }
        case nil: list.notice("対応していないURLです")
        }
    }
    func sceneWillResignActive(_ scene: UIScene) {
        guard let window else { return }
        let view = UIView(frame: window.bounds); view.backgroundColor = .systemBackground
        window.addSubview(view); cover = view
    }
    func sceneDidBecomeActive(_ scene: UIScene) { cover?.removeFromSuperview(); cover = nil }
}

enum ProbeRoute: Equatable {
    case list, create, item(String)
    init?(_ url: URL) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "nibble-probe",
              c.user == nil, c.password == nil, c.port == nil, c.query == nil, c.fragment == nil else { return nil }
        switch c.host {
        case "list" where c.path.isEmpty: self = .list
        case "create" where c.path.isEmpty: self = .create
        case "item":
            let id = String(c.path.dropFirst())
            guard c.path.hasPrefix("/"), UUID(uuidString: id) != nil else { return nil }
            self = .item(id)
        default: return nil
        }
    }
}

@MainActor final class ProbeController: UITableViewController, UISearchResultsUpdating {
    var values: [ProbeValue] = []
    var deleted: ProbeValue?
    var failSaves = false
    let search = UISearchController(searchResultsController: nil)
    var visibleValues: [ProbeValue] {
        let key = SearchProbe.key(search.searchBar.text ?? "")
        return key.isEmpty ? values : values.filter { SearchProbe.key($0.title + "\n" + $0.body).contains(key) }
    }
    let url = URL.documentsDirectory.appending(path: "PROTOTYPE-scratch.store")
    override func viewDidLoad() {
        super.viewDidLoad(); title = "研究用スニペット"
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .add, primaryAction: UIAction { [weak self] _ in self?.edit(nil) })
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "probe.add"
        search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false
        search.hidesNavigationBarDuringPresentation = false
        search.searchBar.placeholder = "タイトルと本文を検索"
        search.searchBar.searchTextField.accessibilityIdentifier = "probe.search"
        navigationItem.searchController = search; navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "復元", primaryAction: UIAction { [weak self] _ in
            guard let self, let deleted else { return }
            do { try persist(values + [deleted]); self.deleted = nil } catch { notice(error.localizedDescription) }
        })
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "probe.undo"
        do { values = try SwiftDataProbe(url: url).values() } catch { notice(error.localizedDescription) }
    }
    func updateSearchResults(for searchController: UISearchController) { tableView.reloadData() }
    func notice(_ message: String) {
        let label = UILabel(); label.text = message; label.textAlignment = .center; label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body); label.adjustsFontForContentSizeCategory = true
        tableView.backgroundView = label
    }
    func persist(_ next: [ProbeValue]) throws {
        if failSaves { throw CocoaError(.fileWriteOutOfSpace) }
        try SwiftDataProbe(url: url).replace(next); values = next; tableView.reloadData()
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visibleValues.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let value = visibleValues[indexPath.row]
        var content = cell.defaultContentConfiguration(); content.text = value.title; content.secondaryText = value.body
        content.secondaryTextProperties.numberOfLines = 2; cell.contentConfiguration = content
        cell.accessibilityIdentifier = "probe.row.\(value.id)"
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { edit(visibleValues[indexPath.row]) }
    func edit(_ value: ProbeValue?) {
        let editor = ProbeEditor(value: value)
        editor.onDelete = { [weak self, weak editor] in
            guard let self, let value, let editor else { return }
            do { try persist(values.filter { $0.id != value.id }); deleted = value; navigationController?.popViewController(animated: true) }
            catch { editor.status.text = "削除失敗: \(error.localizedDescription)" }
        }
        editor.onSave = { [weak self, weak editor] value in
            guard let self, let editor else { return }
            var next = values.filter { $0.id != value.id }; next.append(value)
            do { try persist(next); editor.clearDraft(); navigationController?.popViewController(animated: true) }
            catch { editor.status.text = "保存失敗: \(error.localizedDescription)" }
        }
        navigationController?.pushViewController(editor, animated: true)
    }
}

@MainActor final class ProbeEditor: UIViewController, UITextViewDelegate {
    let value: ProbeValue?
    let name = UITextField()
    let input = UITextView()
    let status = UILabel()
    var onSave: ((ProbeValue) -> Void)?
    var onDelete: (() -> Void)?
    var draftURL: URL { URL.documentsDirectory.appending(path: "draft-" + (value?.id ?? "new") + ".json") }
    func keepDraft() {
        let draft = ProbeValue(id: value?.id ?? "new", title: name.text ?? "", body: input.text ?? "")
        do { try JSONEncoder().encode(draft).write(to: draftURL, options: [.atomic, .completeFileProtection]) }
        catch { status.text = "下書き保存失敗: \(error.localizedDescription)" }
    }
    func clearDraft() { try? FileManager.default.removeItem(at: draftURL) }
    func textViewDidChange(_ textView: UITextView) { keepDraft() }
    init(value: ProbeValue?) { self.value = value; super.init(nibName: nil,bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground; title = "テキストの検証"
        name.placeholder = "タイトル"; name.text = value?.title; name.borderStyle = .roundedRect
        name.font = .preferredFont(forTextStyle: .body); name.adjustsFontForContentSizeCategory = true
        name.addAction(UIAction { [weak self] _ in self?.keepDraft() }, for: .editingChanged)
        name.accessibilityIdentifier = "probe.title"
        input.text = value?.body ?? ""; input.accessibilityIdentifier = "probe.body"
        input.accessibilityLabel = "本文"; input.delegate = self
        if let data = try? Data(contentsOf: draftURL), let draft = try? JSONDecoder().decode(ProbeValue.self, from: data) {
            name.text = draft.title; input.text = draft.body
        }
        input.font = .preferredFont(forTextStyle: .body); input.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0; status.accessibilityIdentifier = "probe.status"
        status.font = .preferredFont(forTextStyle: .footnote); status.adjustsFontForContentSizeCategory = true
        let save = UIButton(type: .system); save.setTitle("保存",for: .normal); save.accessibilityIdentifier = "probe.save"
        save.addAction(UIAction { [weak self] _ in
            guard let self else { return }; view.endEditing(true)
            onSave?(ProbeValue(id: value?.id ?? UUID().uuidString, title: name.text ?? "", body: input.text, revision: (value?.revision ?? 0)+1))
        },for: .touchUpInside)
        let copy = UIButton(type: .system); copy.setTitle("コピー",for: .normal); copy.accessibilityIdentifier = "probe.copy"
        copy.addAction(UIAction { [weak self] _ in
            guard let self else { return }; view.endEditing(true)
            UIPasteboard.general.setItems([["public.utf8-plain-text": input.text ?? ""]],options: [.localOnly:true])
            status.text = "コピーしました"
        },for: .touchUpInside)
        let delete = UIButton(type: .system); delete.setTitle("削除", for: .normal); delete.accessibilityIdentifier = "probe.delete"
        delete.isHidden = value == nil
        delete.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)
        for button in [save,copy,delete] {
            button.titleLabel?.font = .preferredFont(forTextStyle: .body)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.heightAnchor.constraint(greaterThanOrEqualToConstant:44).isActive = true
        }
        let stack = UIStackView(arrangedSubviews: [name,input,save,copy,delete,status])
        stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:12),stack.bottomAnchor.constraint(equalTo:view.keyboardLayoutGuide.topAnchor,constant:-12),name.heightAnchor.constraint(greaterThanOrEqualToConstant:44),save.heightAnchor.constraint(greaterThanOrEqualToConstant:44),copy.heightAnchor.constraint(greaterThanOrEqualToConstant:44)])
    }
}
