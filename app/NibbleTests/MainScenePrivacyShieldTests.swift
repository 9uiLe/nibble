import SwiftUI
import Testing
import UIKit
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Mounted main scene privacy boundary", .serialized)
    @MainActor
    struct MainScenePrivacyShieldTests {
        @Test func inactiveCoverIncludesAPresentedSheetAndRestoresItsNativeInput() async throws {
            let host = try ViewTestHost()
            defer { host.close() }
            let scene = try #require(host.window.windowScene)
            let priorWindows = Set(scene.windows.map(ObjectIdentifier.init))
            host.show(AnyView(MainScenePrivacyShield()), phase: .active)
            try await host.wait {
                scene.windows.contains { !priorWindows.contains(ObjectIdentifier($0)) && $0.accessibilityIdentifier == "workspace.privacy.window" }
            }
            let cover = try #require(scene.windows.first {
                !priorWindows.contains(ObjectIdentifier($0)) && $0.accessibilityIdentifier == "workspace.privacy.window"
            })
            #expect(cover.isHidden && !cover.canBecomeKey)

            let sheet = UIViewController()
            sheet.modalPresentationStyle = .pageSheet
            let input = UITextView()
            input.text = "保持する私的な文章・か\u{3099}👩🏽‍💻"
            input.frame = CGRect(x: 20, y: 20, width: 250, height: 160)
            sheet.view.addSubview(input)
            host.controller.present(sheet, animated: false)
            try await host.wait { sheet.presentingViewController != nil && input.window != nil }
            #expect(input.becomeFirstResponder())
            let original = input.text ?? ""
            input.selectedRange = NSRange(location: 2, length: 3)
            let selection = input.selectedRange
            let keyWindow = scene.windows.first(where: \.isKeyWindow)

            host.show(AnyView(MainScenePrivacyShield()), phase: .inactive)
            try await host.wait { !cover.isHidden }
            #expect(cover.windowScene === scene)
            #expect(cover.windowLevel > host.window.windowLevel)
            #expect(cover.frame == scene.effectiveGeometry.coordinateSpace.bounds)
            #expect(cover.rootViewController?.view.isOpaque == true)
            #expect(cover.rootViewController?.view.backgroundColor == .systemBackground)
            #expect(scene.windows.first(where: \.isKeyWindow) === keyWindow)
            #expect(sheet.presentingViewController === host.controller)
            #expect(input.text.utf8.elementsEqual(original.utf8) && input.selectedRange == selection)

            host.show(AnyView(MainScenePrivacyShield()), phase: .background)
            try await host.wait { !cover.isHidden }
            host.show(AnyView(MainScenePrivacyShield()), phase: .active)
            try await host.wait { cover.isHidden }
            #expect(input.isFirstResponder && input.selectedRange == selection)
            #expect(input.text.utf8.elementsEqual(original.utf8))

            // The native notification must cover synchronously, before a later
            // SwiftUI environment update. This is not an OS snapshot test.
            NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: scene)
            #expect(!cover.isHidden)
            NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
            #expect(cover.isHidden && input.isFirstResponder)

            sheet.dismiss(animated: false)
            host.show(AnyView(EmptyView()))
            try await host.wait { cover.windowScene == nil && cover.rootViewController == nil && cover.isHidden }
        }
    }
}
