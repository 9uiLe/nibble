import SwiftUI
import Testing
import UIKit
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Notice scene and input ownership", .serialized)
    @MainActor
    struct NoticeWindowTests {
        @Test func noticePassesOutsideTouchesAndRetainsTheSourceKeyboardFocus() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let item = try await create(files.store, title: "同名でも区別する長い通知対象の文章", body: "ダミーデータ")
            let model = LibraryModel(store: files.store)
            await model.delete(item)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let host = try NoticeTestHost()
            defer { host.close() }
            let input = UITextField(frame: CGRect(x: 24, y: 160, width: 240, height: 44))
            host.controller.view.addSubview(input)
            try #require(input.becomeFirstResponder())
            let anchor = LibraryNoticeWindow.AnchorView()
            anchor.content = LibraryWindowNotice(model: model, taskOwner: LibraryTaskOwner())
            anchor.isPresented = true
            anchor.bottomBoundary = 280
            host.controller.view.addSubview(anchor)
            anchor.synchronize()
            defer { anchor.dismiss() }
            let overlay = try #require(anchor.noticeWindow)
            try await host.wait { (overlay.noticeView?.bounds.height ?? 0) >= 44 }
            let banner = try #require(overlay.noticeView)
            overlay.layoutIfNeeded()
            let frame = banner.convert(banner.bounds, to: overlay)
            #expect(!overlay.canBecomeKey && !overlay.isKeyWindow)
            #expect(scene.keyWindow === host.window && input.isFirstResponder)
            #expect(overlay.windowScene === host.window.windowScene && overlay.windowLevel > host.window.windowLevel)
            #expect(frame.height >= 44 && frame.maxY <= 281)
            #expect(overlay.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil) != nil)
            #expect(overlay.hitTest(CGPoint(x: 2, y: frame.midY), with: nil) == nil)
            #expect(overlay.hitTest(CGPoint(x: frame.midX, y: frame.maxY + 40), with: nil) == nil)
            model.clearNotice()
            #expect(overlay.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil) == nil)
            await model.restore(item)
            anchor.synchronize()
            #expect(anchor.noticeWindow === overlay && overlay.noticeView === banner)
            #expect(input.isFirstResponder && scene.keyWindow === host.window)
            anchor.isPresented = false
            anchor.synchronize()
            #expect(anchor.noticeWindow == nil && overlay.isHidden && overlay.rootViewController == nil)
        }

        @Test func attachingAndDismantlingTheBridgeOwnsAllOverlayResources() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let model = LibraryModel(store: files.store)
            let host = try NoticeTestHost()
            defer { host.close() }
            let anchor = LibraryNoticeWindow.AnchorView()
            anchor.content = LibraryWindowNotice(model: model, taskOwner: LibraryTaskOwner())
            anchor.isPresented = true
            anchor.bottomBoundary = 300
            anchor.synchronize()
            #expect(anchor.noticeWindow == nil)
            host.controller.view.addSubview(anchor)
            let released = WeakReference(anchor.noticeWindow)
            try #require(released.value != nil)
            anchor.synchronize()
            #expect(anchor.noticeWindow === released.value)
            anchor.removeFromSuperview()
            #expect(anchor.noticeWindow == nil)
            try await host.wait { released.value == nil }
            host.controller.view.addSubview(anchor)
            try #require(anchor.noticeWindow != nil)
            let bridge = LibraryNoticeWindow(model: model, taskOwner: LibraryTaskOwner(), isPresented: true, bottomBoundary: 300)
            LibraryNoticeWindow.dismantleUIView(anchor, coordinator: bridge.makeCoordinator())
            #expect(anchor.noticeWindow == nil && anchor.content == nil)
        }
    }
}

@MainActor
private final class NoticeTestHost {
    let window: UIWindow
    let controller = UIViewController()
    private weak var previousKey: UIWindow?

    init() throws {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try #require(scenes.first)
        previousKey = scene.keyWindow
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previousKey?.makeKey()
    }

    func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "The native notice host did not reach the expected state")
    }
}
