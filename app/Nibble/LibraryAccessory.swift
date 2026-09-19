import AppMacros
import SwiftUI
import UIKit

/// Text and actions only: the system tab accessory owns its background and placement.
@Equatable
struct LibraryAccessory: View {
    private let inputRevision = UUID()
    @SkipEquatable let notifications: LibraryNotifications
    @SkipEquatable let all: LibraryModel
    @SkipEquatable let search: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner

    var body: some View {
        Group {
            if let notice = notifications.notice {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(notice.message, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if let subject = notice.subject {
                            Text(subject).font(.caption).lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(notice.announcement)
                    .accessibilityIdentifier("library.notice")
                    if notice.undoID != nil {
                        Button { taskOwner.startTask(.undoNotice(notice.id), on: notice.sourceTab == .library ? all : search) } label: {
                            Text("元に戻す").font(.subheadline.weight(.semibold))
                                .fixedSize().frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.borderless)
                        .disabled(notice.undoInProgress)
                        .accessibilityIdentifier("library.undo")
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
            }
        }
        .tint(.nibbleAccent)
        .task(id: notifications.notice?.id) {
            if let id = notifications.notice?.id {
                notifications.presented(id: id)
                await notifications.expire(id: id)
            }
        }
    }
}

/// iOS 26.0 has no SwiftUI isEnabled overload. Public UIKit containment keeps the
/// TabView and its list/search state mounted while adding/removing its accessory.
@Equatable(.mainActor)
struct LegacyLibraryAccessory: UIViewControllerRepresentable {
    private let inputRevision = UUID()
    @SkipEquatable let notifications: LibraryNotifications
    let isEnabled: Bool
    @SkipEquatable let all: LibraryModel
    @SkipEquatable let search: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(content: LibraryAccessory(notifications: notifications, all: all, search: search, taskOwner: taskOwner), enabled: isEnabled)
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.detach()
    }

    @MainActor
    final class Controller: UIViewController {
        private var host: UIHostingController<ModifiedContent<LibraryAccessory, NibbleInterface>>?
        private var accessory: UITabAccessory?
        private weak var owner: UITabBarController?
        private var enabled = false

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        func update(content: LibraryAccessory, enabled: Bool) {
            self.enabled = enabled
            let content = content.modifier(NibbleInterface())
            if let host { host.rootView = content }
            else {
                let host = UIHostingController(rootView: content)
                host.sizingOptions = [.intrinsicContentSize]
                host.view.backgroundColor = .clear
                NibbleInterface.apply(to: &host.traitOverrides)
                self.host = host
            }
            attachIfReady()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attachIfReady()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachIfReady()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            attachIfReady()
        }

        private func attachIfReady() {
            guard enabled, let tab = tabBarController, let host else { detach(); return }
            if owner !== tab { detach() }
            if accessory == nil {
                tab.addChild(host)
                let accessory = UITabAccessory(contentView: host.view)
                self.accessory = accessory
                owner = tab
                tab.setBottomAccessory(accessory, animated: false)
                host.didMove(toParent: tab)
            }
        }

        func detach() {
            if let accessory, owner?.bottomAccessory === accessory {
                owner?.setBottomAccessory(nil, animated: false)
            }
            if host?.parent != nil {
                host?.willMove(toParent: nil)
                host?.view.removeFromSuperview()
                host?.removeFromParent()
            }
            accessory = nil
            owner = nil
        }
    }
}
