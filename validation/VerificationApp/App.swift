import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = FixtureViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

/// A disposable fixture for exercising the development tools, not nibble's product UI.
@MainActor
final class FixtureViewController: UIViewController, UITextViewDelegate {
    let input = UITextView()
    let output = UILabel()
    let outputBytes = UILabel()
    let secondInput = UITextView()
    let secondOutput = UILabel()
    let secondOutputBytes = UILabel()
    private let scrollView = UIScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configure(input, id: "fixture.input", name: "確認するテキスト A")
        configure(secondInput, id: "fixture.input.second", name: "確認するテキスト B")
        configure(output, id: "fixture.output", name: "反映した内容 A")
        configure(outputBytes, id: "fixture.output.bytes", name: "A の UTF-8 バイト列")
        configure(secondOutput, id: "fixture.output.second", name: "反映した内容 B")
        configure(secondOutputBytes, id: "fixture.output.second.bytes", name: "B の UTF-8 バイト列")

        let apply = UIButton(configuration: .filled())
        apply.setTitle("反映", for: .normal)
        apply.accessibilityIdentifier = "fixture.apply"
        apply.addAction(UIAction { [weak self] _ in self?.applyText() }, for: .touchUpInside)
        apply.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        let applySecond = UIButton(configuration: .bordered())
        applySecond.setTitle("B を反映", for: .normal)
        applySecond.accessibilityIdentifier = "fixture.apply.second"
        applySecond.addAction(UIAction { [weak self] _ in self?.applySecondText() }, for: .touchUpInside)
        applySecond.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        let reset = UIButton(configuration: .bordered())
        reset.setTitle("リセット", for: .normal)
        reset.accessibilityIdentifier = "fixture.reset"
        reset.addAction(UIAction { [weak self] _ in self?.reset() }, for: .touchUpInside)
        reset.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        let focusFirst = UIButton(configuration: .bordered())
        focusFirst.setTitle("Aを編集", for: .normal)
        focusFirst.accessibilityIdentifier = "fixture.focus.first"
        focusFirst.addAction(UIAction { [weak self] _ in _ = self?.input.becomeFirstResponder() }, for: .touchUpInside)
        focusFirst.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        focusFirst.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        let focusSecond = UIButton(configuration: .bordered())
        focusSecond.setTitle("Bを編集", for: .normal)
        focusSecond.accessibilityIdentifier = "fixture.focus.second"
        focusSecond.addAction(UIAction { [weak self] _ in _ = self?.secondInput.becomeFirstResponder() }, for: .touchUpInside)
        focusSecond.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        focusSecond.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        let header = UIStackView(arrangedSubviews: [label("nibble 検証", style: .title2), reset])
        header.spacing = 12
        let focusActions = UIStackView(arrangedSubviews: [focusFirst, focusSecond])
        focusActions.distribution = .fillEqually
        focusActions.spacing = 12
        let actions = UIStackView(arrangedSubviews: [apply, applySecond])
        actions.distribution = .fillEqually
        actions.spacing = 12
        let stack = UIStackView(arrangedSubviews: [
            label("入力先 A / B は独立した OS の編集欄です。反映は各欄の現在値を読み取ります。", style: .body),
            label("入力先 A", style: .headline), input,
            label("入力先 B", style: .headline), secondInput,
            label("反映した内容 A", style: .headline), output,
            label("A の UTF-8 バイト列", style: .subheadline), outputBytes,
            label("反映した内容 B", style: .headline), secondOutput,
            label("B の UTF-8 バイト列", style: .subheadline), secondOutputBytes,
        ])
        stack.axis = .vertical
        stack.spacing = 16
        scrollView.accessibilityIdentifier = "fixture.scroll"
        scrollView.addSubview(stack)
        for subview in [header, focusActions, scrollView, actions] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            focusActions.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            focusActions.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            focusActions.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: focusActions.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -8),
            actions.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            actions.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            actions.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])
        self.reset()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for input in [input, secondInput] where input.isFirstResponder {
            reveal(input)
        }
    }

    func applyText() {
        observe(input, output: output, bytes: outputBytes)
    }

    func applySecondText() {
        observe(secondInput, output: secondOutput, bytes: secondOutputBytes)
    }

    func reset() {
        input.text = ""
        secondInput.text = ""
        for output in [output, outputBytes, secondOutput, secondOutputBytes] {
            output.text = "未実行"
            output.accessibilityValue = "未実行"
        }
        view.endEditing(true)
        scrollView.setContentOffset(.zero, animated: false)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        view.layoutIfNeeded()
        reveal(textView)
    }

    private func reveal(_ input: UITextView) {
        scrollView.scrollRectToVisible(input.convert(input.bounds, to: scrollView), animated: false)
    }

    private func observe(_ input: UITextView, output: UILabel, bytes: UILabel) {
        let text = input.text ?? ""
        output.text = text
        output.accessibilityValue = text
        let byteText = "[" + text.utf8.map(String.init).joined(separator: ",") + "]"
        bytes.text = byteText
        bytes.accessibilityValue = byteText
        view.endEditing(true)
        view.layoutIfNeeded()
        scrollView.scrollRectToVisible(output.convert(output.bounds, to: scrollView), animated: false)
    }

    private func configure(_ input: UITextView, id: String, name: String) {
        input.font = .preferredFont(forTextStyle: .body)
        input.adjustsFontForContentSizeCategory = true
        input.backgroundColor = .secondarySystemBackground
        input.layer.cornerRadius = 12
        input.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        input.accessibilityIdentifier = id
        input.accessibilityLabel = name
        input.autocorrectionType = .no
        input.autocapitalizationType = .none
        input.delegate = self
        input.heightAnchor.constraint(equalToConstant: 140).isActive = true
    }

    private func configure(_ output: UILabel, id: String, name: String) {
        output.font = .preferredFont(forTextStyle: .body)
        output.adjustsFontForContentSizeCategory = true
        output.numberOfLines = 0
        output.lineBreakMode = .byCharWrapping
        output.accessibilityIdentifier = id
        output.accessibilityLabel = name
    }

    private func label(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }
}
