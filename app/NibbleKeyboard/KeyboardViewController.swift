import KeyboardHostIdentity
import SwiftUI
import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController, PreparedKeyboardDelivery {
    private lazy var model = PreparedKeyboardModel(delivery: self)
    private lazy var owner = PreparedKeyboardTaskOwner(model: model)
    private var heightConstraint: NSLayoutConstraint?

    override func loadView() {
        inputView = UIInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let height = view.heightAnchor.constraint(equalToConstant: 360)
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height
        let globe = UIButton(type: .system)
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.accessibilityLabel = "次のキーボード"
        globe.accessibilityIdentifier = "keyboard.nextKeyboard"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let host = UIHostingController(rootView: PreparedKeyboardView(model: model, owner: owner, globe: globe))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.activate(needsInputModeSwitchKey: needsInputModeSwitchKey)
        owner.startTask(.reload)
    }

    override func viewWillDisappear(_ animated: Bool) {
        model.deactivate()
        owner.cancelAll()
        super.viewWillDisappear(animated)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let requested: CGFloat = traitCollection.verticalSizeClass == .compact ? 196 : 360
        if heightConstraint?.constant != requested {
            heightConstraint?.constant = requested
            view.invalidateIntrinsicContentSize()
        }
        model.updateSwitchKey(needsInputModeSwitchKey)
    }

    override func textWillChange(_ textInput: (any UITextInput)?) {
        model.inputChanged()
        super.textWillChange(textInput)
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        model.inputChanged()
        super.textDidChange(textInput)
    }

    override func selectionWillChange(_ textInput: (any UITextInput)?) {
        model.inputChanged()
        super.selectionWillChange(textInput)
    }

    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        model.inputChanged()
        super.selectionDidChange(textInput)
    }

    func documentIdentifier() -> UUID? { NibbleKeyboardDocumentIdentifier(self) }

    func insert(_ text: String, document: UUID, admission: () -> Bool) -> Bool {
        NibbleKeyboardInsertText(self, text, document, admission)
    }

    func dismiss() { dismissKeyboard() }
}
