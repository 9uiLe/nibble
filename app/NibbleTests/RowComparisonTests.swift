import Observation
import Foundation
import UIKit
import SwiftUI
import Testing
@testable import Nibble

extension UIIntegrationTests {
    @Suite("AppMacros row comparison", .serialized)
    @MainActor
    struct RowComparisonTests {
        @Test func brandColorsKeepTheSamePaletteWhenContrastSettingChanges() {
            func luminance(_ color: UIColor, _ traits: UITraitCollection) -> Double {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                #expect(color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a))
                func linear(_ value: CGFloat) -> Double {
                    let v = Double(value)
                    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
                }
                return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
            }
            for style in [UIUserInterfaceStyle.light, .dark] {
                var ratios: [Double] = []
                for contrast in [UIAccessibilityContrast.normal, .high] {
                    let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style),
                                                               UITraitCollection(accessibilityContrast: contrast)])
                    let accent = luminance(UIColor(Color.nibbleAccent), traits)
                    let canvas = luminance(UIColor(Color.nibbleCanvas), traits)
                    let ratio = (max(accent, canvas) + 0.05) / (min(accent, canvas) + 0.05)
                    #expect(ratio >= 4.5)
                    ratios.append(ratio)
                }
                #expect(ratios[1] == ratios[0])
            }
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
                SnippetRowContent(title: "返信", preview: "確認します", pinned: false,
                                  unusedSince: Date(timeIntervalSince1970: 0)),
            ] {
                let updated = try await render(row)
                #expect(updated != initial)
                let restored = try await render(original)
                #expect(restored == initial)
            }

            let untitled = SnippetRowContent(title: "", preview: "一件目", pinned: false)
            let untitledPixels = try await render(untitled)
            #expect(try await render(SnippetRowContent(title: "", preview: "二件目", pinned: false)) != untitledPixels)
            #expect(try await render(untitled) == untitledPixels)
            #expect(try await render(original) == initial)

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

extension UIIntegrationTests {
    @Test @MainActor
    func fixedInterfaceIgnoresInheritedTextAndContrastTraits() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 300)
        window.overrideUserInterfaceStyle = .light
        let parent = UIViewController()
        let host = UIHostingController(rootView:
            VStack {
                SnippetRowContent(title: "保存した文章", preview: "コピーして使う内容", pinned: true)
                TextField("タイトル", text: .constant("通常サイズの入力"))
                Button("保存") {}.buttonStyle(.borderedProminent).tint(.nibbleAccent)
            }.padding().background(Color.nibbleCanvas).modifier(NibbleInterface())
        )
        NibbleInterface.apply(to: &host.traitOverrides)
        window.rootViewController = parent
        parent.addChild(host)
        host.view.frame = window.bounds
        parent.view.addSubview(host.view)
        host.didMove(toParent: parent)
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }

        func pixels() async throws -> Data {
            try await Task.sleep(for: .milliseconds(100))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return try #require(UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }.pngData())
        }

        parent.traitOverrides.preferredContentSizeCategory = .large
        parent.traitOverrides.legibilityWeight = .regular
        parent.traitOverrides.accessibilityContrast = .normal
        let normal = try await pixels()
        for size in [UIContentSizeCategory.extraSmall, .accessibilityExtraExtraExtraLarge] {
            parent.traitOverrides.preferredContentSizeCategory = size
            parent.traitOverrides.legibilityWeight = .bold
            parent.traitOverrides.accessibilityContrast = .high
            #expect(try await pixels() == normal)
            #expect(host.traitCollection.preferredContentSizeCategory == .large)
            #expect(host.traitCollection.legibilityWeight == .regular)
            #expect(host.traitCollection.accessibilityContrast == .normal)
        }
        // Light/dark appearance remains independent of the fixed accessibility traits.
        window.overrideUserInterfaceStyle = .dark
        #expect(try await pixels() != normal)
    }
}


@MainActor @Observable
private final class FilterSelection {
    var value: LibraryFilter = .all
    var binding: Binding<LibraryFilter> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

extension UIIntegrationTests {
    @Test @MainActor
    func mountedFilterTracksReplacementBindingWithoutRetainingTheOldSource() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldSource = FilterSelection()
        let newSource = FilterSelection()
        let host = UIHostingController(rootView: LibraryFilterBar(selection: oldSource.binding))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 120)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }

        func pixels() async throws -> Data {
            try await Task.sleep(for: .milliseconds(150))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return try #require(UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }.pngData())
        }

        let original = try await pixels()
        host.rootView = LibraryFilterBar(selection: newSource.binding)
        #expect(try await pixels() == original)
        oldSource.value = .drafts
        #expect(try await pixels() == original)
        newSource.value = .pinned
        #expect(try await pixels() != original)
        newSource.value = .all
        #expect(try await pixels() == original)
    }
}
