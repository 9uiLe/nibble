import SwiftUI
import UIKit
import Testing
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Notice window ownership", .serialized)
    @MainActor
    struct NoticeWindowTests {
        @Test(arguments: ["取り消し対象", "長い対象名でも操作結果と元に戻すを読めることを確認する通知の取り消し対象"])
        func overlayKeepsInputInSourceWindowAndPassesOutsideTouches(title: String) async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let id = try await create(files.store, title: title, body: "ダミー本文")
            let model = LibraryModel(store: files.store)
            await model.delete(id)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previousKey = scene.keyWindow
            let source = UIWindow(windowScene: scene)
            source.frame = scene.effectiveGeometry.coordinateSpace.bounds
            let controller = UIViewController()
            source.rootViewController = controller
            source.makeKeyAndVisible()
            defer {
                source.isHidden = true
                source.rootViewController = nil
                previousKey?.makeKey()
            }
            let input = UITextField(frame: CGRect(x: 20, y: 160, width: 240, height: 44))
            let keyboardGuide = controller.view.keyboardLayoutGuide
            controller.view.addSubview(input)
            #expect(input.becomeFirstResponder())
            try await Task.sleep(for: .milliseconds(400))
            let anchor = LibraryNoticeWindow.AnchorView()
            controller.view.addSubview(anchor)
            anchor.content = LibraryWindowNotice(model: model, taskOwner: LibraryTaskOwner())
            anchor.isPresented = true
            anchor.bottomBoundary = controller.view.convert(keyboardGuide.layoutFrame, to: source).minY - 8
            anchor.synchronize()
            defer { anchor.dismiss() }
            try await Task.sleep(for: .milliseconds(400))
            let overlay = try #require(anchor.noticeWindow)
            overlay.layoutIfNeeded()
            let banner = try #require(overlay.noticeView)
            let frame = banner.convert(banner.bounds, to: overlay)
            #expect(overlay.windowScene === source.windowScene)
            #expect(overlay.windowLevel > source.windowLevel)
            #expect(!overlay.canBecomeKey && !overlay.isKeyWindow)
            #expect(scene.keyWindow === source && input.isFirstResponder)
            #expect(frame.height >= 52 && frame.minY >= overlay.safeAreaInsets.top)
            #expect(abs(frame.minX - 16) < 1)
            #expect(abs(frame.maxX - (overlay.bounds.width - 16)) < 1)
            let keyboardTop = controller.view.convert(keyboardGuide.layoutFrame, to: overlay).minY
            #expect(frame.maxY <= keyboardTop - 8 + 1)
            #expect(abs(frame.maxY - anchor.bottomBoundary) < 1)
            let creationTarget = CGPoint(x: overlay.bounds.width - 44, y: overlay.safeAreaInsets.top + 34)
            #expect(overlay.hitTest(creationTarget, with: nil) == nil)
            #expect(overlay.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil) != nil)
            #expect(overlay.hitTest(CGPoint(x: 2, y: frame.midY), with: nil) == nil)
            #expect(overlay.hitTest(CGPoint(x: frame.midX, y: frame.maxY + 30), with: nil) == nil)
            // Expiry keeps the rendering host alive for its fade, but stops intercepting input.
            model.clearNotice()
            try await Task.sleep(for: .milliseconds(100))
            #expect(anchor.noticeWindow === overlay)
            #expect(overlay.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil) == nil)
            // A result arriving during the outgoing animation reuses the same scene and host.
            await model.restore(id)
            try await Task.sleep(for: .milliseconds(400))
            #expect(anchor.noticeWindow === overlay)
            #expect(overlay.noticeView === banner)
            #expect(model.notice?.message == "元に戻しました")
            #expect(overlay.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil) != nil)
            anchor.isPresented = false
            anchor.synchronize()
            #expect(anchor.noticeWindow == nil && overlay.isHidden)
            #expect(overlay.rootViewController == nil)
            #expect(scene.keyWindow === source && input.isFirstResponder)
        }

        @Test func attachmentAndRemovalOwnTheWindowLifetime() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let id = try await create(files.store, body: "ウィンドウの寿命")
            let model = LibraryModel(store: files.store)
            await model.delete(id)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let source = UIWindow(windowScene: scene)
            source.frame = scene.effectiveGeometry.coordinateSpace.bounds
            source.rootViewController = UIViewController()
            source.isHidden = false
            defer { source.isHidden = true; source.rootViewController = nil }
            let anchor = LibraryNoticeWindow.AnchorView()
            anchor.content = LibraryWindowNotice(model: model, taskOwner: LibraryTaskOwner())
            anchor.isPresented = true
            anchor.bottomBoundary = source.bounds.height - 100
            anchor.synchronize()
            #expect(anchor.noticeWindow == nil) // No connected source scene yet.
            source.rootViewController?.view.addSubview(anchor)
            weak var firstWindow = anchor.noticeWindow
            #expect(firstWindow != nil)
            anchor.synchronize()
            #expect(anchor.noticeWindow === firstWindow) // Updates reuse the same window.
            anchor.removeFromSuperview()
            #expect(anchor.noticeWindow == nil)
            try await Task.sleep(for: .milliseconds(100))
            #expect(firstWindow == nil)
            source.rootViewController?.view.addSubview(anchor)
            #expect(anchor.noticeWindow != nil)
            let bridge = LibraryNoticeWindow(model: model, taskOwner: LibraryTaskOwner(), isPresented: true,
                                             bottomBoundary: source.bounds.height - 100)
            let coordinator = bridge.makeCoordinator()
            LibraryNoticeWindow.dismantleUIView(anchor, coordinator: coordinator)
            #expect(anchor.noticeWindow == nil && anchor.content == nil)
        }
    }
}
