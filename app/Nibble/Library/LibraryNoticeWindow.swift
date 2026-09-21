import AppMacros
import SwiftUI
import UIKit

/// Anchors transient results to this scene without changing the content's safe area.
@Equatable(.mainActor)
struct LibraryNoticeWindow: UIViewRepresentable {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    let isPresented: Bool
    let bottomBoundary: CGFloat

    func makeUIView(context: Context) -> AnchorView { AnchorView() }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.content = LibraryWindowNotice(model: model, taskOwner: taskOwner)
        view.isPresented = isPresented
        view.bottomBoundary = bottomBoundary
        view.synchronize()
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: ()) {
        view.isPresented = false
        view.content = nil
        view.dismiss()
    }

    final class AnchorView: UIView {
        var content: LibraryWindowNotice?
        var isPresented = false
        var bottomBoundary: CGFloat = 0
        private(set) var noticeWindow: NoticeOverlayWindow?
        private var host: UIHostingController<LibraryWindowNotice>?
        private var bottomConstraint: NSLayoutConstraint?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            synchronize()
        }

        func synchronize() {
            guard isPresented, bottomBoundary > 0, let content, let scene = window?.windowScene else {
                dismiss()
                return
            }
            if let noticeWindow, noticeWindow.windowScene === scene {
                bottomConstraint?.constant = bottomBoundary
                host?.rootView = content
                noticeWindow.hasNotice = { [weak model = content.model] in model?.notice != nil }
                return
            }
            dismiss()
            let overlay = NoticeOverlayWindow(windowScene: scene)
            let controller = UIViewController()
            let host = UIHostingController(rootView: content)
            host.sizingOptions = .intrinsicContentSize
            host.safeAreaRegions = []
            host.view.backgroundColor = .clear
            controller.view.backgroundColor = .clear
            controller.addChild(host)
            controller.view.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            // SwiftUI supplies its usable bottom edge, including tabs and keyboard.
            // Keep keyboard tracking in the content window, never in this auxiliary window.
            let bottom = host.view.bottomAnchor.constraint(
                equalTo: controller.view.topAnchor, constant: bottomBoundary)
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(greaterThanOrEqualTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: InterfaceMetrics.noticeSpacing),
                host.view.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor, constant: InterfaceMetrics.noticeMargin),
                host.view.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -InterfaceMetrics.noticeMargin),
                bottom,
            ])
            host.didMove(toParent: controller)
            overlay.frame = scene.effectiveGeometry.coordinateSpace.bounds
            overlay.windowLevel = .init(rawValue: UIWindow.Level.normal.rawValue + 1)
            overlay.backgroundColor = .clear
            overlay.rootViewController = controller
            overlay.noticeView = host.view
            overlay.hasNotice = { [weak model = content.model] in model?.notice != nil }
            NibbleInterface.apply(to: &overlay.traitOverrides)
            self.host = host
            bottomConstraint = bottom
            noticeWindow = overlay
            // Showing an auxiliary window must not move text input out of the app window.
            overlay.isHidden = false
        }

        func dismiss() {
            noticeWindow?.rootViewController?.view.removeFromSuperview()
            noticeWindow?.isHidden = true
            noticeWindow?.rootViewController = nil
            noticeWindow?.windowScene = nil
            noticeWindow = nil
            host = nil
            bottomConstraint = nil
        }
    }
}

/// Restrict hit testing to the hosted banner, leaving the list and keyboard operable.
final class NoticeOverlayWindow: UIWindow {
    weak var noticeView: UIView?
    var hasNotice: () -> Bool = { false }

    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard hasNotice(), let noticeView, !isHidden, alpha > 0,
              noticeView.bounds.contains(noticeView.convert(point, from: self)) else { return nil }
        return super.hitTest(point, with: event)
    }
}
