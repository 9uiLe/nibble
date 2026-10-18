import SwiftUI
import UIKit
import KeyboardHostIdentity

@MainActor
final class KeyboardViewController: UIInputViewController, KeyboardEffects {
    private lazy var model = KeyboardModel(reader: KeyboardReader(), effects: self, proIsActive: ProAccess.isActive)
    private var generation = UUID()
    private var held: KeyboardInputLease?
    private var visible = false
    private var heightConstraint: NSLayoutConstraint?
    private var preferredHeight: CGFloat = 288
    var destination: KeyboardDestination {
        observeHeldDocument()
        if let held { return .init(document: held.destinationDocument, revision: generation) }
        return .init(document: NibbleKeyboardDocumentIdentifier(self), revision: generation)
    }
    var canCopy: Bool { hasFullAccess }
    override func loadView() { inputView = UIInputView(frame: .zero, inputViewStyle: .keyboard) }
    override func viewDidLoad() {
        super.viewDidLoad()
        NibbleInterface.apply(to: &traitOverrides)
        let height = view.heightAnchor.constraint(equalToConstant: 288)
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height
        let globe = UIButton(type: .system)
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.tintColor = .label
        globe.accessibilityLabel = "次のキーボード"
        globe.accessibilityIdentifier = "keyboard.nextKeyboard"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let host = UIHostingController(rootView: KeyboardView(model: model, globe: globe, setPreferredHeight: { [weak self] value in
            self?.preferredHeight = value
            self?.updateHeight()
        }).modifier(NibbleInterface()))
        host.view.backgroundColor = .clear
        NibbleInterface.apply(to: &host.traitOverrides)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.updateCapabilities(fullAccess: hasFullAccess, needsSwitchKey: needsInputModeSwitchKey)
        model.activate()
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); visible = true }
    override func viewWillDisappear(_ animated: Bool) {
        visible = false
        generation = UUID()
        model.deactivate()
        super.viewWillDisappear(animated)
    }
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateHeight()
        model.updateCapabilities(fullAccess: hasFullAccess, needsSwitchKey: needsInputModeSwitchKey)
    }
    private func updateHeight() {
        let value = min(preferredHeight, traitCollection.verticalSizeClass == .compact ? 196 : 400)
        guard heightConstraint?.constant != value else { return }
        heightConstraint?.constant = value
        view.invalidateIntrinsicContentSize()
    }
    override func textWillChange(_ textInput: (any UITextInput)?) {
        invalidateDestination()
        super.textWillChange(textInput)
    }
    override func selectionWillChange(_ textInput: (any UITextInput)?) {
        invalidateDestination()
        super.selectionWillChange(textInput)
    }
    func holdInputDocument(_ expected: KeyboardDestination) -> Bool {
        guard let document = expected.document else { return false }
        held = KeyboardInputLease(document: document)
        return destination == expected
    }
    override func textDidChange(_ textInput: (any UITextInput)?) {
        invalidateDestination()
        super.textDidChange(textInput)
        observeHeldDocument()
    }
    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        invalidateDestination()
        super.selectionDidChange(textInput)
        observeHeldDocument()
    }
    func releaseInputDocument() { held = nil }
    private func invalidateDestination() {
        generation = UUID()
        held?.invalidate()
    }
    private func observeHeldDocument() {
        let document = NibbleKeyboardDocumentIdentifier(self)
        guard var current = held else { return }
        current.observe(document: document)
        held = current
    }
    func insert(_ text: String, into expected: KeyboardDestination) -> Bool {
        guard let document = expected.document, destination == expected else { return false }
        return NibbleKeyboardInsertText(self, text, document) { [weak self] in
            guard let self, visible, model.isCurrent, generation == expected.revision else { return false }
            return held.map { $0.destinationDocument == expected.document } ?? true
        }
    }
    func copy(_ text: String) { UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true]) }
    func dismiss() { dismissKeyboard() }
}
