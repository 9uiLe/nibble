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
final class FixtureViewController: UIViewController {
    let input = UITextView()
    let output = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = label("nibble 検証", style: .largeTitle)
        let explanation = label("入力・操作・画面記録の確認用アプリです。", style: .body)
        let inputLabel = label("確認するテキスト", style: .headline)
        input.font = .preferredFont(forTextStyle: .body)
        input.adjustsFontForContentSizeCategory = true
        input.backgroundColor = .secondarySystemBackground
        input.layer.cornerRadius = 12
        input.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        input.accessibilityIdentifier = "fixture.input"
        input.accessibilityLabel = "確認するテキスト"
        input.autocorrectionType = .no
        input.autocapitalizationType = .none
        input.heightAnchor.constraint(equalToConstant: 140).isActive = true

        let apply = UIButton(configuration: .filled())
        apply.setTitle("反映", for: .normal)
        apply.accessibilityIdentifier = "fixture.apply"
        apply.addAction(UIAction { [weak self] _ in self?.applyText() }, for: .touchUpInside)
        apply.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        output.text = "未実行"
        output.accessibilityLabel = "反映した内容"
        output.accessibilityValue = "未実行"
        output.font = .preferredFont(forTextStyle: .body)
        output.adjustsFontForContentSizeCategory = true
        output.numberOfLines = 0
        output.accessibilityIdentifier = "fixture.output"

        let reset = UIButton(configuration: .bordered())
        reset.setTitle("リセット", for: .normal)
        reset.accessibilityIdentifier = "fixture.reset"
        reset.addAction(UIAction { [weak self] _ in
            self?.input.text = ""
            self?.output.text = "未実行"
            self?.output.accessibilityValue = "未実行"
            self?.view.endEditing(true)
        }, for: .touchUpInside)
        reset.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        let stack = UIStackView(arrangedSubviews: [title, explanation, inputLabel, input, apply,
                                                   label("反映した内容", style: .headline), output, reset])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
    }

    func applyText() {
        output.text = input.text
        output.accessibilityValue = input.text
        view.endEditing(true)
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
