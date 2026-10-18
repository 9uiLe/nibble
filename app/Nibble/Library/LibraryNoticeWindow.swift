import AppMacros
import SwiftUI
import UIKit

@Equatable(.mainActor)
struct LibraryNoticeWindow: UIViewRepresentable {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    let isPresented: Bool
    let bottomBoundary: CGFloat
    func makeUIView(context: Context) -> AnchorView { AnchorView() }
    func updateUIView(_ anchor: AnchorView, context: Context) {
        anchor.content = LibraryWindowNotice(model: model, taskOwner: taskOwner)
        anchor.isPresented = isPresented
        anchor.bottomBoundary = bottomBoundary
        anchor.synchronize()
    }
    static func dismantleUIView(_ anchor: AnchorView, coordinator: ()) {
        anchor.content = nil
        anchor.isPresented = false
        anchor.dismiss()
    }
    final class AnchorView: UIView {
        var content: LibraryWindowNotice?
        var isPresented = false
        var bottomBoundary: CGFloat = 0
        private(set) var noticeWindow: NoticeOverlayWindow?
        private var controller: UIHostingController<LibraryWindowNotice>?
        private var bottom: NSLayoutConstraint?
        override func didMoveToWindow() { super.didMoveToWindow(); synchronize() }
        func synchronize() {
            guard let scene = window?.windowScene, isPresented, bottomBoundary > 0, let content else { dismiss(); return }
            if let overlay = noticeWindow, overlay.windowScene === scene {
                bottom?.constant = bottomBoundary
                if controller?.rootView.model !== content.model || controller?.rootView.taskOwner !== content.taskOwner {
                    controller?.rootView = content
                    overlay.hasNotice = { [weak model = content.model] in model?.notice != nil }
                }
                return
            }
            dismiss()
            let overlay = NoticeOverlayWindow(windowScene: scene)
            let host = UIHostingController(rootView: content)
            let holder = UIViewController()
            host.sizingOptions = .intrinsicContentSize
            host.safeAreaRegions = []
            holder.view.backgroundColor = .clear
            host.view.backgroundColor = .clear
            holder.addChild(host)
            holder.view.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            let bottom = host.view.bottomAnchor.constraint(equalTo: holder.view.topAnchor, constant: bottomBoundary)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: holder.view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                host.view.trailingAnchor.constraint(equalTo: holder.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                host.view.topAnchor.constraint(greaterThanOrEqualTo: holder.view.safeAreaLayoutGuide.topAnchor, constant: 8), bottom
            ])
            host.didMove(toParent: holder)
            overlay.rootViewController = holder
            overlay.frame = scene.effectiveGeometry.coordinateSpace.bounds
            overlay.windowLevel = .init(rawValue: UIWindow.Level.normal.rawValue + 1)
            overlay.backgroundColor = .clear
            overlay.noticeView = host.view
            overlay.hasNotice = { [weak model = content.model] in model?.notice != nil }
            NibbleInterface.apply(to: &overlay.traitOverrides)
            self.bottom = bottom
            controller = host
            noticeWindow = overlay
            overlay.isHidden = false
        }
        func dismiss() {
            guard let overlay = noticeWindow else { return }
            overlay.isHidden = true
            overlay.rootViewController = nil
            overlay.windowScene = nil
            noticeWindow = nil
            controller = nil
            bottom = nil
        }
    }
}

final class NoticeOverlayWindow: UIWindow {
    weak var noticeView: UIView?
    var hasNotice: () -> Bool = { false }
    override var canBecomeKey: Bool { false }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, hasNotice(), let noticeView,
              noticeView.bounds.contains(noticeView.convert(point, from: self)) else { return nil }
        return super.hitTest(point, with: event)
    }
}
