import Foundation
import Observation
import SwiftUI
import Testing
import UIKit
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Mounted display inputs", .serialized)
    @MainActor
    struct RowComparisonTests {
        @Test func eachRowValueAndAppearanceReachesTheMountedHierarchy() async throws {
            let host = try ViewTestHost()
            defer { host.close() }
            let image = DisplayImage(host: host)
            let initial = AnyView(SnippetRowContent(title: "返信", preview: "確認します", pinned: false).padding())
            host.show(initial)
            let original = try await image.capture()
            var previous = original
            for row in [
                SnippetRowContent(title: "予定", preview: "確認します", pinned: false),
                SnippetRowContent(title: "予定", preview: "明日確認します", pinned: false),
                SnippetRowContent(title: "予定", preview: "明日確認します", pinned: true),
                SnippetRowContent(title: "予定", preview: "明日確認します", pinned: true, unusedSince: Date(timeIntervalSince1970: 0))
            ] {
                host.show(AnyView(row.padding()))
                let next = try await image.capture()
                #expect(next != previous)
                previous = next
            }
            host.show(initial)
            #expect(try await image.capture() == original)
            host.show(initial, scheme: .dark)
            #expect(try await image.capture() != original)
        }

        @Test func replacingABindingDetachesTheOldSourceAndKeepsNewChangesLive() async throws {
            let host = try ViewTestHost()
            defer { host.close() }
            let image = DisplayImage(host: host)
            let first = DisplaySelection()
            let replacement = DisplaySelection()
            host.show(AnyView(LibraryFilterBar(selection: first.binding)))
            let original = try await image.capture()
            host.show(AnyView(LibraryFilterBar(selection: replacement.binding)))
            #expect(try await image.capture() == original)
            first.value = .drafts
            #expect(try await image.capture() == original)
            replacement.value = .pinned
            #expect(try await image.capture() != original)
            replacement.value = .all
            #expect(try await image.capture() == original)
        }

        @Test func fixedTextTraitsRemainIndependentOfLightAndDarkAppearance() async throws {
            let host = try ViewTestHost()
            defer { host.close() }
            NibbleInterface.apply(to: &host.controller.traitOverrides)
            let image = DisplayImage(host: host)
            let content = AnyView(VStack {
                SnippetRowContent(title: "保存した文章", preview: "何度も使う本文", pinned: true)
                TextField("任意のタイトル", text: .constant("標準サイズ"))
                Button("保存") { }.buttonStyle(.borderedProminent)
            }.padding())
            host.show(content)
            let original = try await image.capture()
            for size in [UIContentSizeCategory.extraSmall, .accessibilityExtraExtraExtraLarge] {
                host.window.traitOverrides.preferredContentSizeCategory = size
                host.window.traitOverrides.legibilityWeight = .bold
                host.window.traitOverrides.accessibilityContrast = .high
                #expect(try await image.capture() == original)
                #expect(host.controller.traitCollection.preferredContentSizeCategory == .large)
                #expect(host.controller.traitCollection.legibilityWeight == .regular)
                #expect(host.controller.traitCollection.accessibilityContrast == .normal)
            }
            host.show(content, scheme: .dark)
            #expect(try await image.capture() != original)
        }

        @Test func semanticForegroundsMeetTheirDeclaredContrastOnBothAppearances() {
            let pairs: [(Color, Color, Double)] = [
                (.nibblePrimary, .nibbleCanvas, 4.5), (.nibblePrimary, .nibbleSurface, 4.5),
                (.nibbleSecondary, .nibbleCanvas, 4.5), (.nibbleSecondary, .nibbleSurface, 4.5),
                (.nibbleSecondary, .nibbleSoft, 4.5), (.nibbleAccent, .nibbleCanvas, 4.5),
                (.nibbleAccent, .nibbleSurface, 4.5), (.nibbleAccent, .nibbleSoft, 4.5),
                (.nibbleOnAccent, .nibbleAccent, 4.5), (.nibbleOnSelection, .nibbleSelection, 4.5),
                (.nibbleBorder, .nibbleCanvas, 3), (.nibbleBorder, .nibbleSurface, 3),
                (.nibbleErrorText, .nibbleSoft, 4.5), (.nibbleErrorText, .nibbleSurface, 4.5),
                (.white, .nibbleDestructive, 4.5),
                (.nibbleKeyboardAccent, .nibbleCanvas, 4.5),
                (.nibbleKeyboardAccent, .nibbleSurface, 4.5),
                (.nibbleKeyboardAccent, .nibbleSoft, 4.5),
                (.nibbleKeyboardAccent, .nibbleKeyboardHighlight, 4.5),
                (.nibblePrimary, .nibbleKeyboardHighlight, 4.5),
                (.nibbleSecondary, .nibbleKeyboardHighlight, 4.5),
                (IOSDesignTokens.nibbleKeyboard.colors.primaryForeground,
                 IOSDesignTokens.nibbleKeyboard.colors.primary, 4.5)
            ]
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                for (foreground, background, minimum) in pairs {
                    let a = relativeLuminance(UIColor(foreground), traits: traits)
                    let b = relativeLuminance(UIColor(background), traits: traits)
                    #expect((max(a, b) + 0.05) / (min(a, b) + 0.05) >= minimum)
                }
            }
        }
    }
}

@MainActor @Observable
private final class DisplaySelection {
    var value = LibraryFilter.all
    var binding: Binding<LibraryFilter> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
private struct DisplayImage {
    let host: ViewTestHost
    func capture() async throws -> Data {
        // UIKit commits the mounted hierarchy on its next display passes.
        try await Task.sleep(for: .milliseconds(100))
        let view = try #require(host.controller.view)
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
        let pixels = renderer.image { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
        return try #require(pixels.pngData())
    }
}

@MainActor
private func relativeLuminance(_ color: UIColor, traits: UITraitCollection) -> Double {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    #expect(color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    let channels = [red, green, blue].map { value in
        let component = Double(value)
        return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
}
