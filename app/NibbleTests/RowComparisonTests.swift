import Foundation
import UIKit
import SwiftUI
import Testing
@testable import Nibble

extension UIIntegrationTests {
    @Suite("AppMacros row comparison", .serialized)
    @MainActor
    struct RowComparisonTests {
        @Test func everyDisplayedInputParticipatesInEquality() {
            let row = SnippetRowContent(title: "返信", preview: "確認します", pinned: false)
            #expect(row == SnippetRowContent(title: "返信", preview: "確認します", pinned: false))
            #expect(row != SnippetRowContent(title: "予定", preview: "確認します", pinned: false))
            #expect(row != SnippetRowContent(title: "返信", preview: "明日確認します", pinned: false))
            #expect(row != SnippetRowContent(title: "返信", preview: "確認します", pinned: true))
            // A body-derived heading must also invalidate when its preview changes.
            #expect(SnippetRowContent(title: "", preview: "一件目", pinned: false)
                    != SnippetRowContent(title: "", preview: "二件目", pinned: false))
        }

        @Test func mountedRowUpdatesAndReturnsToTheSamePixels() async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let original = SnippetRowContent(title: "返信", preview: "確認します", pinned: false)
            let host = UIHostingController(rootView: original)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 160)
            window.overrideUserInterfaceStyle = .light
            host.traitOverrides.preferredContentSizeCategory = .large
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }

            func pixels() throws -> Data {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format)
                let image = renderer.image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                return try #require(image.pngData())
            }

            // Await the mounted hierarchy's render pass; no task is created inside the helper.
            func render(_ row: SnippetRowContent) async throws -> Data {
                host.rootView = row
                try await Task.sleep(for: .milliseconds(100))
                return try pixels()
            }

            let initial = try await render(original)
            for row in [
                SnippetRowContent(title: "予定", preview: "確認します", pinned: false),
                SnippetRowContent(title: "返信", preview: "明日確認します", pinned: false),
                SnippetRowContent(title: "返信", preview: "確認します", pinned: true),
                SnippetRowContent(title: "", preview: "本文から見出し", pinned: false),
            ] {
                let updated = try await render(row)
                #expect(updated != initial)
                let restored = try await render(original)
                #expect(restored == initial)
            }

            // Equal row inputs must not freeze environment updates in Text/Image.
            window.overrideUserInterfaceStyle = .dark
            try await Task.sleep(for: .milliseconds(100))
            #expect(try pixels() != initial)
            window.overrideUserInterfaceStyle = .light
            try await Task.sleep(for: .milliseconds(100))
            #expect(try pixels() == initial)

            host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            try await Task.sleep(for: .milliseconds(100))
            #expect(try pixels() != initial)
            host.traitOverrides.preferredContentSizeCategory = .large
            try await Task.sleep(for: .milliseconds(100))
            #expect(try pixels() == initial)
        }
    }
}
