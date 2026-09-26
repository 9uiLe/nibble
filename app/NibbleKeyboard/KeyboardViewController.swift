import SwiftUI
import UIKit

/// UIKit owns the host input connection; the model never reads surrounding text.
@MainActor
final class KeyboardViewController: UIInputViewController, KeyboardEffects {
    private lazy var model = KeyboardModel(reader: KeyboardReader(), effects: self, proIsActive: ProAccess.isActive)
    private var selectionRevision = UUID()
    private var keyboardHeight: NSLayoutConstraint?
    private var requestedHeight: CGFloat = 288
    // The value field changes UIKit's current document; retain the host proxy for insertion.
    private var heldInputDocument: (proxy: any UITextDocumentProxy, id: UUID, editingID: UUID)?

    var destination: KeyboardDestination {
        if let heldInputDocument {
            let currentID = heldInputDocument.proxy.documentIdentifier
            return KeyboardDestination(document: currentID == heldInputDocument.editingID ? heldInputDocument.id : currentID,
                                       revision: selectionRevision)
        }
        return KeyboardDestination(document: textDocumentProxy.documentIdentifier, revision: selectionRevision)
    }
    var canCopy: Bool { hasFullAccess }

    override func loadView() {
        inputView = UIInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NibbleInterface.apply(to: &traitOverrides)
        // Reserve two control rows and several summaries without obscuring the host document.
        let height = view.heightAnchor.constraint(equalToConstant: 288)
        height.priority = .defaultHigh
        height.isActive = true
        keyboardHeight = height
        let globe = UIButton(type: .system)
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.tintColor = .label
        globe.accessibilityLabel = "次のキーボード"
        globe.accessibilityIdentifier = "keyboard.nextKeyboard"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let host = UIHostingController(rootView: KeyboardView(model: model, globe: globe,
            setPreferredHeight: { [weak self] in self?.setPreferredHeight($0) }).modifier(NibbleInterface()))
        NibbleInterface.apply(to: &host.traitOverrides)
        // Keep the system keyboard surface visible through the SwiftUI content.
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateCapabilities()
        model.activate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        model.deactivate()
        super.viewWillDisappear(animated)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateKeyboardHeight()
        updateCapabilities()
    }

    private func setPreferredHeight(_ height: CGFloat) {
        requestedHeight = height
        updateKeyboardHeight()
    }

    private func updateKeyboardHeight() {
        let limit: CGFloat = traitCollection.verticalSizeClass == .compact ? 196 : 288
        let height = min(requestedHeight, limit)
        guard keyboardHeight?.constant != height else { return }
        keyboardHeight?.constant = height
        view.invalidateIntrinsicContentSize()
    }

    override func textWillChange(_ textInput: (any UITextInput)?) {
        selectionRevision = UUID()
        super.textWillChange(textInput)
    }

    override func selectionWillChange(_ textInput: (any UITextInput)?) {
        selectionRevision = UUID()
        super.selectionWillChange(textInput)
    }

    private func updateCapabilities() {
        model.updateCapabilities(fullAccess: hasFullAccess, needsSwitchKey: needsInputModeSwitchKey)
    }

    func holdInputDocument() {
        let proxy = textDocumentProxy
        let id = proxy.documentIdentifier
        heldInputDocument = (proxy, id, id)
    }
    func noteVariableValueEditing() {
        guard var held = heldInputDocument else { return }
        held.editingID = held.proxy.documentIdentifier
        heldInputDocument = held
    }
    func releaseInputDocument() { heldInputDocument = nil }
    func insert(_ text: String) { (heldInputDocument?.proxy ?? textDocumentProxy).insertText(text) }
    func copy(_ text: String) {
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
    }
    func dismiss() { dismissKeyboard() }
}
