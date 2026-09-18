import SwiftUI
import UIKit

/// UIKit owns the host input connection; the model never reads surrounding text.
@MainActor
final class KeyboardViewController: UIInputViewController, KeyboardEffects {
    private lazy var model = KeyboardModel(reader: KeyboardReader(), effects: self)
    private var selectionRevision = UUID()
    private var keyboardHeight: NSLayoutConstraint?

    var destination: KeyboardDestination {
        KeyboardDestination(document: textDocumentProxy.documentIdentifier, revision: selectionRevision)
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
        let host = UIHostingController(rootView: KeyboardView(model: model, globe: globe).modifier(NibbleInterface()))
        // Keep the system keyboard surface visible through the SwiftUI content.
        host.view.backgroundColor = .clear
        NibbleInterface.apply(to: &host.traitOverrides)
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
        let height: CGFloat = traitCollection.verticalSizeClass == .compact ? 196 : 288
        if keyboardHeight?.constant != height { keyboardHeight?.constant = height }
        updateCapabilities()
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

    func insert(_ text: String) { textDocumentProxy.insertText(text) }
    func copy(_ text: String) {
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
    }
    func dismiss() { dismissKeyboard() }
}
