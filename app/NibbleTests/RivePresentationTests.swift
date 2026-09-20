import Foundation
import RivePresentation
import RiveRuntime
import Testing
import SwiftUI
import UIKit
@testable import Nibble

extension UIIntegrationTests {
    @Test @MainActor
    func keyboardIllustrationPausesOffscreenAndKeepsItsSession() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        func content(_ phase: ScenePhase, _ scheme: ColorScheme, shown: Bool = true) -> some View {
            Group {
                if shown { KeyboardGuideView() }
            }
            .environment(\.scenePhase, phase)
            .environment(\.colorScheme, scheme)
            .modifier(NibbleInterface())
        }
        let host = UIHostingController(rootView: content(.active, .light))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
            if let match = view as? T { return match }
            return view.subviews.lazy.compactMap { find(type, in: $0) }.first
        }
        func wait(_ condition: () -> Bool) async throws {
            for _ in 0..<100 {
                host.view.layoutIfNeeded()
                if condition() { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(condition(), "Mounted illustration did not reach the required playback state")
        }
        try await wait { find(RiveUIView.self, in: host.view)?.isPaused == false }
        let first = try #require(find(RiveUIView.self, in: host.view))
        let rive = try #require(first.rive)
        let scroll = try #require(find(UIScrollView.self, in: host.view))
        scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
        try await wait { first.isPaused }
        host.rootView = content(.active, .dark)
        try await wait { find(RiveUIView.self, in: host.view) !== first }
        let recolored = try #require(find(RiveUIView.self, in: host.view))
        #expect(recolored.isPaused)
        #expect(recolored.rive === rive)
        let data = try #require(rive.viewModelInstance)
        #expect(try await data.value(of: ColorProperty(path: "paper")).argbValue == 0xFF25282C)
        scroll.setContentOffset(.zero, animated: false)
        try await wait { !recolored.isPaused }
        host.rootView = content(.background, .dark)
        try await wait { recolored.isPaused }
        host.rootView = content(.active, .dark)
        try await wait { !recolored.isPaused }
        host.rootView = content(.active, .dark, shown: false)
        // Rive invalidates its frame clock when detached from the window; isPaused
        // records the explicit pause request, not this separate lifetime boundary.
        try await wait { recolored.window == nil }
        host.rootView = content(.active, .dark)
        try await wait { find(RiveUIView.self, in: host.view)?.isPaused == false }
        let reopened = try #require(find(RiveUIView.self, in: host.view))
        #expect(reopened.rive !== rive)
    }

    @Test @MainActor
    func keyboardStoryBindingsAndIndependentSessions() async throws {
        let resource = try await RiveResource.load(named: "keyboard-story", in: .main)
        let first = try await resource.makeSession(KeyboardIllustration.contract)
        let second = try await resource.makeSession(KeyboardIllustration.contract)
        #expect(try await first.data.value(of: BoolProperty(path: "motionAllowed")))

        // The exported default instance and all palette bindings must work in the Apple runtime.
        let dark: [(String, UInt32)] = [
            ("paper", 0xFF25282C), ("ink", 0xFFF1F1EF), ("accent", 0xFFFFA366),
            ("muted", 0xFF727980), ("action", 0xFF72B5FF)
        ]
        for (name, value) in dark {
            first.data.setValue(of: ColorProperty(path: name), to: RiveRuntime.Color(value))
            #expect(try await first.data.value(of: ColorProperty(path: name)).argbValue == value)
        }
        #expect(try await second.data.value(of: ColorProperty(path: "action")).argbValue == 0xFF2878CB)

        first.data.setValue(of: BoolProperty(path: "motionAllowed"), to: false)
        first.rive.stateMachine.advance(by: 1.0 / 60)
        #expect(try await first.data.value(of: BoolProperty(path: "active")) == false)
        #expect(try await second.data.value(of: BoolProperty(path: "motionAllowed")))
        first.data.setValue(of: BoolProperty(path: "motionAllowed"), to: true)
        for _ in 0..<1020 { first.rive.stateMachine.advance(by: 1.0 / 60) }
        #expect(try await first.data.value(of: BoolProperty(path: "active")))

        do {
            _ = try await resource.makeSession(RiveContract(
                artboard: "Keyboard", stateMachine: "Presentation", viewModel: "KeyboardStory",
                properties: ["action": .boolean]
            ))
            Issue.record("A changed keyboard palette contract must fail before display")
        } catch RiveContractError.property(let model, let name) {
            #expect(model == "KeyboardStory")
            #expect(name == "action")
        }
    }

    @Test @MainActor
    func riveContractAndIndependentSessions() async throws {
        let resource = try await RiveResource.load(named: "about-story", in: .main)
        let first = try await resource.makeSession(AboutIllustration.contract)
        let second = try await resource.makeSession(AboutIllustration.contract)
        first.data.setValue(of: BoolProperty(path: "motionAllowed"), to: false)
        first.rive.stateMachine.advance(by: 1.0 / 60)
        #expect(try await first.data.value(of: BoolProperty(path: "motionAllowed")) == false)
        #expect(try await first.data.value(of: BoolProperty(path: "active")) == false)
        #expect(try await second.data.value(of: BoolProperty(path: "motionAllowed")))
        first.data.setValue(of: BoolProperty(path: "motionAllowed"), to: true)
        first.rive.stateMachine.advance(by: 1.0 / 60)
        #expect(try await first.data.value(of: BoolProperty(path: "active")))
        do {
            _ = try await resource.makeSession(RiveContract(
                artboard: "About", stateMachine: "Presentation", viewModel: "AboutStory",
                properties: ["motionAllowed": .number]
            ))
            Issue.record("A changed asset property type must fail before display")
        } catch RiveContractError.property(let model, let name) {
            #expect(model == "AboutStory")
            #expect(name == "motionAllowed")
        }
    }
}
