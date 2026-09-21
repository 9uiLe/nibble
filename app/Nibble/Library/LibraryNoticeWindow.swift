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

    func makeUIView(context: Context) -> AnchorView { AnchorView() }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.content = LibraryWindowNotice(model: model, taskOwner: taskOwner)
        view.isPresented = isPresented
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
        private(set) var noticeWindow: NoticeOverlayWindow?
        private var host: UIHostingController<LibraryWindowNotice>?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            synchronize()
        }

        func synchronize() {
            guard isPresented, let content, let scene = window?.windowScene else {
                dismiss()
                return
            }
            if let noticeWindow, noticeWindow.windowScene === scene {
                host?.rootView = content
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
            let width = host.view.widthAnchor.constraint(equalTo: controller.view.widthAnchor, constant: -32)
            width.priority = .defaultHigh
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 8),
                host.view.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
                host.view.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
                width,
            ])
            host.didMove(toParent: controller)
            overlay.frame = scene.effectiveGeometry.coordinateSpace.bounds
            overlay.windowLevel = .init(rawValue: UIWindow.Level.normal.rawValue + 1)
            overlay.backgroundColor = .clear
            overlay.rootViewController = controller
            overlay.noticeView = host.view
            NibbleInterface.apply(to: &overlay.traitOverrides)
            self.host = host
            noticeWindow = overlay
            // Showing an auxiliary window must not move text input out of the app window.
            overlay.isHidden = false
        }

        func dismiss() {
            noticeWindow?.isHidden = true
            noticeWindow?.rootViewController = nil
            noticeWindow = nil
            host = nil
        }
    }
}

/// Restrict hit testing to the hosted banner, leaving the list and keyboard operable.
final class NoticeOverlayWindow: UIWindow {
    weak var noticeView: UIView?

    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let noticeView, !isHidden, alpha > 0,
              noticeView.bounds.contains(noticeView.convert(point, from: self)) else { return nil }
        return super.hitTest(point, with: event)
    }
}

@Equatable
struct LibraryWindowNotice: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner

    var body: some View {
        LibraryNotice(model: model, restore: { taskOwner.startTask(.undoNotice($0), on: model) }, inWindow: true)
            .tint(.nibbleAccent)
            .modifier(NibbleInterface())
            .privacySensitive()
    }
}
