import AppMacros
import SwiftUI
import UIKit

@MainActor @Equatable(.mainActor)
struct MainScenePrivacyShield: UIViewRepresentable {
    @Environment(\.scenePhase) private var phase

    func makeUIView(context: Context) -> Probe {
        Probe()
    }

    func updateUIView(_ view: Probe, context: Context) {
        view.setShielded(phase != .active)
    }

    static func dismantleUIView(_ view: Probe, coordinator: ()) {
        view.detach()
    }

    final class Probe: UIView {
        private weak var scene: UIWindowScene?
        private var shield: UIWindow?
        private var requestedShield = true
        private var sceneAllowsContent = false

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
        }

        required init?(coder: NSCoder) { return nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let next = window?.windowScene else { detach(); return }
            guard scene !== next else { return }
            detach()
            scene = next
            sceneAllowsContent = next.activationState == .foregroundActive
            let cover = ShieldWindow(windowScene: next)
            cover.accessibilityIdentifier = "workspace.privacy.window"
            cover.windowLevel = .alert + 1
            cover.isUserInteractionEnabled = false
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            controller.view.isOpaque = true
            controller.view.accessibilityIdentifier = "workspace.privacy.shield"
            cover.rootViewController = controller
            shield = cover
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(willDeactivate), name: UIScene.willDeactivateNotification, object: next)
            center.addObserver(self, selector: #selector(willDeactivate), name: UIScene.didEnterBackgroundNotification, object: next)
            center.addObserver(self, selector: #selector(didActivate), name: UIScene.didActivateNotification, object: next)
            applyVisibility()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let scene else { return }
            shield?.frame = scene.effectiveGeometry.coordinateSpace.bounds
        }

        func setShielded(_ requested: Bool) {
            requestedShield = requested
            applyVisibility()
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            shield?.isHidden = true
            shield?.rootViewController = nil
            shield?.windowScene = nil
            shield = nil
            scene = nil
        }

        @objc private func willDeactivate() {
            sceneAllowsContent = false
            applyVisibility()
        }

        @objc private func didActivate() {
            sceneAllowsContent = true
            applyVisibility()
        }

        private func applyVisibility() {
            guard let shield, let scene else { return }
            shield.frame = scene.effectiveGeometry.coordinateSpace.bounds
            // A separate non-key window covers presentations without resigning
            // their input or changing the work session underneath it.
            shield.isHidden = !(requestedShield || !sceneAllowsContent)
        }
    }

    private final class ShieldWindow: UIWindow {
        override var canBecomeKey: Bool { false }
    }
}
