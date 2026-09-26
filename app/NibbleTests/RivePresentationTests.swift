import Foundation
import RivePresentation
import RiveRuntime
import Testing
import SwiftUI
import UIKit
import MetalKit
import AppMacros
import Observation
@testable import Nibble

extension UIIntegrationTests {
    @Test @MainActor
    func drawingCoalescesUntilAcquisitionReturnsAndDoesNotResumeDismissedView() async throws {
        let resource = try await RiveResource.load(named: "about-story", in: .main)
        let session = try await resource.makeSession(AboutIllustration.contract)
        let log = RivePlaybackLog()
        let previous = RiveLog.logger
        RiveLog.logger = log
        defer { RiveLog.logger = previous }
        let host = try ViewTestHost()
        defer { host.close() }
        host.show(AnyView(RiveCanvas(session: session, paused: true).frame(width: 300, height: 200)))
        try await host.wait { !log.advances.isEmpty }
        try await Task.sleep(for: .milliseconds(500))
        let metal = try #require(host.find(MTKView.self))
        weak var native: RiveUIView? = try #require(host.find(RiveUIView.self))
        // Wake a settled controller without changing its drawable dimensions.
        session.rive.backgroundColor = RiveRuntime.Color(0x01000000)
        try await Task.sleep(for: .milliseconds(50))
        native?.isPaused = false
        log.reset()
        // The main actor cannot receive the asynchronous acquisition result
        // until this synchronous burst returns. Keep only one pending frame.
        for _ in 0..<32 { native?.draw(in: metal) }
        #expect(log.advances.count == 1, "Pending acquisition must coalesce further frame requests")
        let advancesBeforeDismissal = log.advances.count
        host.show(AnyView(EmptyView()))
        try await host.wait { native?.rive == nil }
        try await Task.sleep(for: .milliseconds(100))
        #expect(log.advances.count == advancesBeforeDismissal, "A result arriving after dismissal must not restart the clock")
    }

    @Test @MainActor
    func loadingUsesTheAppearanceAtCompletion() async throws {
        let host = try ViewTestHost()
        defer { host.close() }
        let probe = IllustrationLoadProbe()
        probe.fails = false
        probe.holdsResult = true
        let playback = IllustrationPlayback(loadResource: probe.load)
        func show(_ scheme: ColorScheme) {
            host.show(AnyView(ScrollView { AboutIllustration(playback: playback) }), scheme: scheme)
        }
        show(.dark)
        try await host.wait { probe.continuation != nil }
        show(.light)
        try await Task.sleep(for: .milliseconds(100))
        probe.continuation?.resume()
        probe.continuation = nil
        try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
        let session = try #require(playback.session)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await session.data.value(of: ColorProperty(path: "paper")).argbValue == 0xFFFFFDFC)
    }

    @Test @MainActor
    func keyboardTabReturnKeepsTheCurrentPalette() async throws {
        let host = try ViewTestHost()
        defer { host.close() }
        let navigation = RiveNavigationProbe()
        navigation.keyboard = true
        navigation.scheme = .dark
        host.show(AnyView(RiveNavigationHost(navigation: navigation)))
        navigation.path = [1]
        try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
        let session = try #require(navigation.playback.session)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await session.data.value(of: ColorProperty(path: "paper")).argbValue == 0xFF25282C)
        navigation.scheme = .light
        try await Task.sleep(for: .milliseconds(150))
        #expect(try await session.data.value(of: ColorProperty(path: "paper")).argbValue == 0xFFFFFDFC)
        let native = try #require(host.find(RiveUIView.self))
        navigation.tab = 1
        try await host.wait { native.isPaused || native.window == nil }
        navigation.tab = 0
        try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
        try await Task.sleep(for: .milliseconds(150))
        #expect(try await session.data.value(of: ColorProperty(path: "paper")).argbValue == 0xFFFFFDFC)
        #expect(host.find(RiveUIView.self) === native)
        host.show(AnyView(EmptyView()))
    }

    @Test @MainActor
    func navigationTabsAndFullScreenCoverKeepPlaybackUntilPop() async throws {
        let host = try ViewTestHost()
        defer { host.close() }
        let navigation = RiveNavigationProbe()
        navigation.scheme = .dark
        host.show(AnyView(RiveNavigationHost(navigation: navigation)))
        navigation.path = [1]
        try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await host.find(RiveUIView.self)?.rive?.viewModelInstance?.value(of: ColorProperty(path: "paper")).argbValue == 0xFF25282C)
        navigation.scheme = .light
        try await Task.sleep(for: .milliseconds(150))
        #expect(try await host.find(RiveUIView.self)?.rive?.viewModelInstance?.value(of: ColorProperty(path: "paper")).argbValue == 0xFFFFFDFC)
        weak var native = host.find(RiveUIView.self)
        weak var rive = native?.rive
        navigation.tab = 1
        try await host.wait { native?.isPaused == true || native?.window == nil }
        navigation.tab = 0
        try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
        #expect(host.find(RiveUIView.self)?.rive === rive)
        try await Task.sleep(for: .milliseconds(150))
        #expect(try await host.find(RiveUIView.self)?.rive?.viewModelInstance?.value(of: ColorProperty(path: "paper")).argbValue == 0xFFFFFDFC)
        navigation.covered = true
        try await host.wait { native?.isPaused == true || native?.window == nil }
        navigation.covered = false
        try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
        #expect(host.find(RiveUIView.self)?.rive === rive)
        navigation.path = []
        try await host.wait { native == nil && rive == nil }
        navigation.path = [1]
        try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
    }

    @Test @MainActor
    func canvasCombinesStopsAndResumesWithoutElapsedPauseTime() async throws {
        let resource = try await RiveResource.load(named: "about-story", in: .main)
        let session = try await resource.makeSession(AboutIllustration.contract)
        let log = RivePlaybackLog()
        let previous = RiveLog.logger
        RiveLog.logger = log
        defer { RiveLog.logger = previous }
        let host = try ViewTestHost()
        defer { host.close() }
        func show(paused: Bool, phase: ScenePhase, revision: Int = 0, width: CGFloat = 300) {
            host.show(AnyView(RiveCanvas(session: session, paused: paused, renderingRevision: revision)
                .frame(width: width, height: 200)), phase: phase)
        }
        show(paused: false, phase: .active)
        try await host.wait { log.advances.contains { $0.delta > 0 } }
        let original = try #require(host.find(RiveUIView.self))
        // Clearing just one reason must never restart the runtime clock.
        for (index, state) in [(true, ScenePhase.active), (true, .background),
                                 (false, .background), (false, .inactive), (true, .inactive), (true, .active)].enumerated() {
            let (paused, phase) = state
            show(paused: paused, phase: phase)
            // Let SwiftUI apply each input even when the prior viewport was paused.
            try await Task.sleep(for: .milliseconds(20))
            try await host.wait { original.isPaused }
            if index == 0 || index == 2 {
                try await Task.sleep(for: .milliseconds(150))
                let count = log.advances.count
                try await Task.sleep(for: .milliseconds(200))
                #expect(log.advances.count == count)
            }
            #expect(host.find(RiveUIView.self) === original)
        }
        let stopped = log.advances.count
        show(paused: false, phase: .active)
        try await host.wait { log.advances.count > stopped }
        #expect(log.advances[stopped].delta == 0)
        show(paused: true, phase: .active)
        try await host.wait { original.isPaused }
        try await Task.sleep(for: .milliseconds(150))
        let position = log.advances.reduce(0) { $0 + $1.delta }
        session.data.setValue(of: ColorProperty(path: "paper"), to: RiveRuntime.Color(0xFF25282C))
        let beforePalette = log.advances.count
        show(paused: true, phase: .active, revision: 1)
        try await host.wait { log.advances.count > beforePalette }
        let recolored = try #require(host.find(RiveUIView.self))
        #expect(recolored.rive === session.rive)
        #expect(recolored.isPaused)
        #expect(original.isPaused && original.rive == nil)
        #expect(try await session.data.value(of: ColorProperty(path: "paper")).argbValue == 0xFF25282C)
        let beforeResize = log.advances.count
        show(paused: true, phase: .active, revision: 1, width: 240)
        try await host.wait { log.advances.count > beforeResize }
        #expect(host.find(RiveUIView.self) === recolored)
        #expect(try #require(host.find(MTKView.self)).drawableSize.width == 240 * host.window.screen.scale)
        #expect(log.advances.reduce(0) { $0 + $1.delta } == position)
        try await Task.sleep(for: .milliseconds(200))
        let stable = log.advances.count
        try await Task.sleep(for: .milliseconds(200))
        #expect(log.advances.count == stable)
        host.show(AnyView(EmptyView()))
        try await host.wait { recolored.window == nil }
        try await Task.sleep(for: .milliseconds(500))
        let beforeRemount = log.advances.count
        show(paused: false, phase: .active)
        try await host.wait { log.advances.count > beforeRemount }
        #expect(log.advances[beforeRemount].delta == 0)
        #expect(host.find(RiveUIView.self)?.rive === session.rive)
    }

    @Test @MainActor
    func illustrationsWaitForVisibilityAndKeepTheirViewportAcrossHostStops() async throws {
        let host = try ViewTestHost()
        defer { host.close() }
        let playback = IllustrationPlayback()
        func show(allowed: Bool) {
            host.show(AnyView(ScrollView {
                VStack {
                    Color.clear.frame(height: 900)
                    AboutIllustration(playback: playback)
                    Color.clear.frame(height: 900)
                }
            }.environment(\.illustrationPlaybackAllowed, allowed)))
        }
        show(allowed: true)
        try await host.wait { host.find(RiveUIView.self) != nil }
        let native = try #require(host.find(RiveUIView.self))
        let session = try #require(playback.session)
        #expect(native.isPaused)
        let scroll = try #require(host.find(UIScrollView.self))
        let rectangle = native.convert(native.bounds, to: scroll)
        for fraction in [0.11, 0.09] {
            scroll.setContentOffset(CGPoint(x: 0, y: rectangle.maxY - rectangle.height * fraction
                    - scroll.adjustedContentInset.top), animated: false)
            try await host.wait { native.isPaused == (fraction < 0.1) }
            #expect(host.find(RiveUIView.self) === native)
            #expect(playback.session === session)
        }
        scroll.setContentOffset(CGPoint(x: 0, y: rectangle.minY - scroll.adjustedContentInset.top), animated: false)
        try await host.wait { !native.isPaused }
        show(allowed: false)
        try await host.wait { native.isPaused }
        show(allowed: true)
        try await host.wait { !native.isPaused }
        #expect(host.find(RiveUIView.self) === native)
        host.show(AnyView(EmptyView()))
        try await host.wait { native.rive == nil }
    }

    @Test @MainActor
    func independentCanvasesReleaseTheirOwnedResources() async throws {
        let host = try ViewTestHost()
        defer { host.close() }
        var first: IllustrationPlayback? = IllustrationPlayback()
        var second: IllustrationPlayback? = IllustrationPlayback()
        await first?.load(named: "about-story", contract: AboutIllustration.contract)
        await second?.load(named: "about-story", contract: AboutIllustration.contract)
        weak var firstSession = first?.session
        weak var secondSession = second?.session
        weak var firstFile = firstSession?.rive.file
        weak var secondFile = secondSession?.rive.file
        #expect(firstSession !== secondSession)
        firstSession?.data.setValue(of: ColorProperty(path: "paper"), to: RiveRuntime.Color(0xFF25282C))
        #expect(try await firstSession?.data.value(of: ColorProperty(path: "paper")).argbValue == 0xFF25282C)
        #expect(try await secondSession?.data.value(of: ColorProperty(path: "paper")).argbValue == 0xFFFFFDFC)
        host.show(AnyView(HStack {
            RiveCanvas(session: first!.session!, paused: true)
            RiveCanvas(session: second!.session!)
        }.frame(height: 200)))
        try await host.wait { host.find(RiveUIView.self) != nil }
        weak var native = host.find(RiveUIView.self)
        first = nil
        second = nil
        host.show(AnyView(EmptyView()))
        try await host.wait {
            firstSession == nil && secondSession == nil && firstFile == nil && secondFile == nil && native == nil
        }
    }

    @Test @MainActor
    func illustrationLoadFailureRetryAndCancellation() async throws {
        let host = try ViewTestHost()
        defer { host.close() }
        let probe = IllustrationLoadProbe()
        let playback = IllustrationPlayback { name, bundle in try await probe.load(name, bundle) }
        host.show(AnyView(ScrollView { AboutIllustration(playback: playback) }))
        try await host.wait { playback.failed }
        #expect(playback.session == nil)
        #expect(host.find(RiveUIView.self) == nil)
        probe.fails = false
        // This tests the recovery operation. The actual retry-button gesture is a
        // separate UI-driver condition, not claimed by this hosted contract test.
        await playback.load(named: "about-story", contract: AboutIllustration.contract)
        #expect(!playback.failed && playback.session != nil)
        try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
        host.show(AnyView(EmptyView()))
        try await host.wait { host.find(RiveUIView.self) == nil }

        let held = IllustrationLoadProbe()
        held.fails = false
        held.holdsResult = true
        let cancelled = IllustrationPlayback { name, bundle in try await held.load(name, bundle) }
        host.show(AnyView(ScrollView { KeyboardIllustration(playback: cancelled) }))
        try await host.wait { held.continuation != nil }
        host.show(AnyView(EmptyView()))
        try await Task.sleep(for: .milliseconds(100))
        held.continuation?.resume()
        held.continuation = nil
        try await host.wait { held.returned }
        #expect(held.wasCancelled)
        #expect(cancelled.session == nil && !cancelled.failed)
        held.holdsResult = false
        host.show(AnyView(ScrollView { KeyboardIllustration(playback: cancelled) }))
        try await host.wait { cancelled.session != nil && host.find(RiveUIView.self)?.isPaused == false }
    }

    @Test @MainActor
    func keyboardIllustrationPausesOffscreenAndKeepsItsSession() async throws {
        let host = try ViewTestHost()
        defer { host.close() }
        host.show(AnyView(KeyboardGuideView()))
        try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
        let first = try #require(host.find(RiveUIView.self))
        let rive = try #require(first.rive)
        let scroll = try #require(host.find(UIScrollView.self))
        scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
        try await host.wait { first.isPaused }
        host.show(AnyView(KeyboardGuideView()), scheme: .dark)
        try await host.wait { host.find(RiveUIView.self) !== first }
        let recolored = try #require(host.find(RiveUIView.self))
        #expect(recolored.isPaused && recolored.rive === rive)
        let data = try #require(rive.viewModelInstance)
        #expect(try await data.value(of: ColorProperty(path: "paper")).argbValue == 0xFF25282C)
        scroll.setContentOffset(.zero, animated: false)
        try await host.wait { !recolored.isPaused }
        host.show(AnyView(EmptyView()))
        try await host.wait { recolored.window == nil }
        host.show(AnyView(KeyboardGuideView()), scheme: .dark)
        try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
        #expect(host.find(RiveUIView.self)?.rive !== rive)
    }

    @Test @MainActor
    func incompatibleAssetPropertyFailsBeforeDisplay() async throws {
        let resource = try await RiveResource.load(named: "about-story", in: .main)
        do {
            _ = try await resource.makeSession(RiveContract(
                artboard: "About", stateMachine: "Presentation", viewModel: "AboutStory",
                properties: ["motionAllowed": .number]
            ))
            Issue.record("A changed asset property type must fail before display")
        } catch RiveContractError.property(let model, let name) {
            #expect(model == "AboutStory" && name == "motionAllowed")
        }
    }
}

@MainActor
private final class IllustrationLoadProbe {
    var fails = true
    var holdsResult = false
    var returned = false
    var wasCancelled = false
    var continuation: CheckedContinuation<Void, Never>?

    func load(_ name: String, _ bundle: Bundle) async throws -> RiveResource {
        let resource = try await RiveResource.load(named: fails ? "missing-illustration-test" : name, in: bundle)
        if holdsResult { await withCheckedContinuation { continuation = $0 } }
        wasCancelled = Task.isCancelled
        returned = true
        return resource
    }
}

@MainActor @Observable
private final class RiveNavigationProbe {
    var path: [Int] = []
    var tab = 0
    var covered = false
    var scheme: ColorScheme = .light
    var keyboard: Bool?
    let playback = IllustrationPlayback()
}

@Equatable
private struct RiveNavigationHost: View {
    private let inputRevision = UUID()
    @Bindable var navigation: RiveNavigationProbe

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("Guide", systemImage: "info.circle", value: 0) {
                NavigationStack(path: $navigation.path) {
                    Text("Settings")
                        .navigationDestination(for: Int.self) { _ in
                            if let keyboard = navigation.keyboard {
                                ScrollView {
                                    if keyboard { KeyboardIllustration(playback: navigation.playback) }
                                    else { AboutIllustration(playback: navigation.playback) }
                                }
                            } else { AboutView() }
                        }
                }
                .environment(\.illustrationPlaybackAllowed, navigation.tab == 0 && !navigation.covered)
            }
            Tab("Other", systemImage: "list.bullet", value: 1) { Text("Other") }
        }
        .environment(\.colorScheme, navigation.scheme)
        .fullScreenCover(isPresented: $navigation.covered) { Text("Cover") }
    }
}
