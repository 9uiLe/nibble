import Foundation
import Darwin
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
    func loadingUsesTheAppearanceAtCompletion() async throws {
        let host = try RiveTestHost()
        defer { host.close() }
        for keyboard in [false, true] {
            let probe = IllustrationLoadProbe()
            probe.fails = false
            probe.holdsResult = true
            let playback = IllustrationPlayback(loadResource: probe.load)
            func show(_ scheme: ColorScheme) {
                host.show(AnyView(ScrollView {
                    if keyboard { KeyboardIllustration(playback: playback) }
                    else { AboutIllustration(playback: playback) }
                }), scheme: scheme)
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
            host.show(AnyView(EmptyView()))
        }
    }

    @Test @MainActor
    func tabReturnKeepsTheCurrentPaletteAfterAppearanceChanges() async throws {
        let host = try RiveTestHost()
        defer { host.close() }
        for keyboard in [false, true] {
            let navigation = RiveNavigationProbe()
            navigation.keyboard = keyboard
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
    }

    @Test @MainActor
    func navigationTabsAndFullScreenCoverKeepPlaybackUntilPop() async throws {
        let host = try RiveTestHost()
        defer { host.close() }
        let navigation = RiveNavigationProbe()
        host.show(AnyView(RiveNavigationHost(navigation: navigation)))
        navigation.path = [1]
        try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
        weak var native = host.find(RiveUIView.self)
        weak var rive = native?.rive
        navigation.tab = 1
        try await host.wait { native?.isPaused == true || native?.window == nil }
        navigation.tab = 0
        try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
        #expect(host.find(RiveUIView.self)?.rive === rive)
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
        let host = try RiveTestHost()
        defer { host.close() }
        func show(paused: Bool, phase: ScenePhase, revision: Int = 0, width: CGFloat = 300) {
            host.show(AnyView(RiveCanvas(session: session, paused: paused, renderingRevision: revision)
                .frame(width: width, height: 200)), phase: phase)
        }
        show(paused: false, phase: .active)
        try await host.wait { log.advances.contains { $0.delta > 0 } }
        let original = try #require(host.find(RiveUIView.self))
        // Clearing just one reason must never restart the runtime clock.
        for (paused, phase) in [(true, ScenePhase.active), (true, .background),
                                 (false, .background), (false, .inactive), (true, .inactive), (true, .active)] {
            show(paused: paused, phase: phase)
            try await host.wait { original.isPaused }
            try await Task.sleep(for: .milliseconds(150))
            let count = log.advances.count
            try await Task.sleep(for: .milliseconds(200))
            #expect(log.advances.count == count)
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
        try await host.wait { recolored.rive == nil && recolored.window == nil }
        #expect(recolored.isPaused)
        try await Task.sleep(for: .milliseconds(500))
        let beforeRemount = log.advances.count
        show(paused: false, phase: .active)
        try await host.wait { log.advances.count > beforeRemount }
        #expect(log.advances[beforeRemount].delta == 0)
        #expect(host.find(RiveUIView.self)?.rive === session.rive)
    }

    @Test @MainActor
    func illustrationsWaitForVisibilityAndKeepTheirViewportAcrossHostStops() async throws {
        let host = try RiveTestHost()
        defer { host.close() }
        for keyboard in [false, true] {
            let playback = IllustrationPlayback()
            func show(allowed: Bool) {
                host.show(AnyView(ScrollView {
                    VStack {
                        Color.clear.frame(height: 900)
                        if keyboard { KeyboardIllustration(playback: playback) }
                        else { AboutIllustration(playback: playback) }
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
            for _ in 0..<3 {
                for fraction in [0.11, 0.09] {
                    scroll.setContentOffset(CGPoint(x: 0, y: rectangle.maxY - rectangle.height * fraction
                        - scroll.adjustedContentInset.top), animated: false)
                    try await host.wait { native.isPaused == (fraction < 0.1) }
                    #expect(host.find(RiveUIView.self) === native)
                    #expect(playback.session === session)
                }
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
    }

    @Test @MainActor
    func independentCanvasesReleaseTheirSessionsAndWorkers() async throws {
        let host = try RiveTestHost()
        defer { host.close() }
        for _ in 0..<3 {
            var first: IllustrationPlayback? = IllustrationPlayback()
            var second: IllustrationPlayback? = IllustrationPlayback()
            await first?.load(named: "about-story", contract: AboutIllustration.contract)
            await second?.load(named: "about-story", contract: AboutIllustration.contract)
            weak var firstSession = first?.session
            weak var secondSession = second?.session
            weak var file = firstSession?.rive.file
            // The pinned 6.27.0 File keeps its worker internal. Reflection is confined
            // to this ownership test, and a missing field fails rather than skips it.
            weak var worker = try #require(Mirror(reflecting: try #require(file)).children
                .first { $0.label == "worker" }?.value as? Worker)
            firstSession?.data.setValue(of: BoolProperty(path: "motionAllowed"), to: false)
            host.show(AnyView(HStack {
                RiveCanvas(session: first!.session!, paused: true)
                RiveCanvas(session: second!.session!)
            }.frame(height: 200)))
            try await host.wait { host.find(RiveUIView.self) != nil }
            try await Task.sleep(for: .milliseconds(100))
            #expect(firstSession !== secondSession)
            #expect(try await firstSession?.data.value(of: BoolProperty(path: "active")) == false)
            #expect(try await secondSession?.data.value(of: BoolProperty(path: "active")) == true)
            weak var native = host.find(RiveUIView.self)
            first = nil
            second = nil
            host.show(AnyView(EmptyView()))
            try await host.wait {
                firstSession == nil && secondSession == nil && file == nil && worker == nil && native == nil
            }
        }
    }

    @Test @MainActor
    func illustrationLoadFailureRetryAndCancellation() async throws {
        let host = try RiveTestHost()
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

    /// The logger observes the real runtime clock; it never advances a machine itself.
    /// Keep these samples separate from presented-frame latency and hitch measurements.
    @Test @MainActor
    func rivePlaybackMeasurements() async throws {
        let log = RivePlaybackLog()
        let previous = RiveLog.logger
        RiveLog.logger = log
        defer { RiveLog.logger = previous }
        let host = try RiveTestHost()
        defer { host.close() }
        var samples: [[String: Double]] = []
        for keyboard in [false, true] {
            for iteration in 0..<6 {
                log.reset()
                let start = ProcessInfo.processInfo.systemUptime
                host.show(keyboard ? AnyView(KeyboardGuideView()) : AnyView(AboutView()))
                try await host.wait { !log.advances.isEmpty }
                weak var native = host.find(RiveUIView.self)
                weak var rive = native?.rive
                weak var file = rive?.file
                let firstAdvance = try #require(log.advances.first)
                try await Task.sleep(for: .milliseconds(350))
                let displayedMemory = try riveFootprint()
                let created = log.count("Initializing view")
                let scroll = try #require(host.find(UIScrollView.self))
                scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
                try await host.wait { native?.isPaused == true }
                try await Task.sleep(for: .milliseconds(150))
                let stopped = log.advances.count
                try await Task.sleep(for: .milliseconds(300))
                #expect(log.advances.count == stopped)
                let resumedAt = ProcessInfo.processInfo.systemUptime
                scroll.setContentOffset(.zero, animated: false)
                try await host.wait { log.advances.count > stopped }
                let resumed = log.advances[stopped]
                #expect(resumed.delta == 0)
                #expect(host.find(RiveUIView.self) === native)
                #expect(log.count("Initializing view") == created)
                host.show(AnyView(EmptyView()))
                try await host.wait { native == nil && rive == nil && file == nil }
                try await Task.sleep(for: .milliseconds(100))
                let closedMemory = try riveFootprint()
                #expect((firstAdvance.time - start) * 1000 <= (iteration == 0 ? 200 : 100))
                #expect((resumed.time - resumedAt) * 1000 <= 100)
                #expect(created == 1)
                    samples.append([
                        "keyboard": keyboard ? 1 : 0,
                        "iteration": Double(iteration),
                        "displayed_footprint_bytes": displayedMemory,
                        "closed_footprint_bytes": closedMemory,
                        "mount_to_first_advance_ms": (firstAdvance.time - start) * 1000,
                        "visibility_request_to_resume_advance_ms": (resumed.time - resumedAt) * 1000,
                        "native_views_created": Double(created),
                        "files_created": Double(log.count("Initializing file")),
                        "workers_created": Double(log.count("Initializing worker"))
                    ])
            }
        }
        for keyboard in [0.0, 1.0] {
            let memory = samples.filter { $0["keyboard"] == keyboard && $0["iteration"] != 0 }
                .compactMap { $0["closed_footprint_bytes"] }
            #expect(try #require(memory.max()) - #require(memory.min()) <= 8 * 1024 * 1024)
        }
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
        Attachment.record(data, named: "rive-playback-measurements.json")
    }

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

/// Main-actor window hosting used only by the serialized UI integration suite.
@MainActor
private final class RiveTestHost {
    let window: UIWindow
    let controller = UIHostingController(rootView: AnyView(EmptyView()))

    init() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        window.rootViewController = controller
        window.isHidden = false
    }

    func show(_ content: AnyView, phase: ScenePhase = .active, scheme: ColorScheme = .light) {
        controller.rootView = AnyView(content.environment(\.scenePhase, phase)
            .environment(\.colorScheme, scheme).modifier(NibbleInterface()))
    }

    func close() {
        controller.rootView = AnyView(EmptyView())
        window.isHidden = true
        window.rootViewController = nil
    }

    func find<T: UIView>(_ type: T.Type) -> T? {
        func search(_ view: UIView) -> T? {
            if let match = view as? T { return match }
            return view.subviews.lazy.compactMap { search($0) }.first
        }
        return search(controller.view)
    }

    func wait(sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath,
                                                             line: #line, column: #column),
              _ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            controller.view.layoutIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Real Canvas did not reach its expected state within two seconds", sourceLocation: sourceLocation)
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

/// Bounded to one test, with locked storage because Rive logs from worker threads too.
private final class RivePlaybackLog: RiveLog.Logger, @unchecked Sendable {
    struct Advance {
        let time: TimeInterval
        let delta: TimeInterval
    }
    private let lock = NSLock()
    private var messages: [String] = []
    private var frames: [Advance] = []
    var advances: [Advance] { lock.withLock { frames } }

    func reset() { lock.withLock { messages.removeAll(); frames.removeAll() } }
    func count(_ text: String) -> Int { lock.withLock { messages.filter { $0.contains(text) }.count } }
    func debug(tag: RiveLog.Tag, _ message: @escaping () -> String) {
        let value = message()
        lock.withLock { messages.append(value) }
    }
    func trace(tag: RiveLog.Tag, _ message: @escaping () -> String) {
        guard tag == .view else { return }
        let value = message()
        let prefix = "[RiveUIView] Advancing state machine (dt="
        guard value.hasPrefix(prefix), let delta = Double(value.dropFirst(prefix.count).dropLast()) else { return }
        let frame = Advance(time: ProcessInfo.processInfo.systemUptime, delta: delta)
        lock.withLock { frames.append(frame) }
    }
    func notice(tag: RiveLog.Tag, _ message: @escaping () -> String) { }
    func info(tag: RiveLog.Tag, _ message: @escaping () -> String) { }
    func error(tag: RiveLog.Tag, error: (any Error)?, _ message: @escaping () -> String) { }
    func warning(tag: RiveLog.Tag, _ message: @escaping () -> String) { }
    func fault(tag: RiveLog.Tag, _ message: @escaping () -> String) { }
    func critical(tag: RiveLog.Tag, _ message: @escaping () -> String) { }
}

private func riveFootprint() throws -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    try #require(result == KERN_SUCCESS)
    return Double(info.phys_footprint)
}
