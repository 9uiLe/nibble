import AppMacros
import Foundation
import MetalKit
import Observation
import RivePresentation
import RiveRuntime
import SwiftUI
import Testing
import UIKit
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Rive ownership and interrupted work", .serialized)
    @MainActor
    struct RiveLifecycleTests {
        @Test func disappearingDuringDecodeRejectsTheLateResourceAndAllowsAnotherVisit() async throws {
            let loader = LifecycleResourceBarrier()
            let playback = IllustrationPlayback(loadResource: loader.load)
            let host = try ViewTestHost()
            defer { loader.release(); host.close() }
            host.show(AnyView(ScrollView { AboutIllustration(playback: playback) }))
            try await host.wait { loader.isSuspended }
            #expect(playback.session == nil)

            host.show(AnyView(EmptyView()))
            try await host.wait { loader.cancellation.wasCancelled }
            loader.release()
            try await host.wait { loader.returned == 1 }
            #expect(playback.session == nil && !playback.failed)

            host.show(AnyView(ScrollView { AboutIllustration(playback: playback) }))
            try await host.wait { playback.session != nil && host.find(RiveUIView.self)?.isPaused == false }
            #expect(loader.returned == 2 && !playback.failed)
        }

        @Test func firstDisplayedPaletteUsesTheAppearanceAfterTheAwait() async throws {
            let loader = LifecycleResourceBarrier()
            let playback = IllustrationPlayback(loadResource: loader.load)
            let host = try ViewTestHost()
            defer { loader.release(); host.close() }
            host.show(AnyView(ScrollView { KeyboardIllustration(playback: playback) }), scheme: .dark)
            try await host.wait { loader.isSuspended }
            #expect(host.find(RiveUIView.self) == nil)
            host.show(AnyView(ScrollView { KeyboardIllustration(playback: playback) }), scheme: .light)
            loader.release()
            try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
            let data = try #require(playback.session?.data)
            #expect(try await data.value(of: ColorProperty(path: "paper")).argbValue == 0xFFFFFDFC)
            #expect(try await data.value(of: ColorProperty(path: "action")).argbValue == 0xFF2878CB)
            #expect(try await data.value(of: BoolProperty(path: "motionAllowed")))
        }

        @Test func crossingTheVisibilityThresholdChangesOnlyThePlaybackGate() async throws {
            let playback = IllustrationPlayback()
            let host = try ViewTestHost()
            defer { host.close() }
            host.show(AnyView(ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 850)
                    KeyboardIllustration(playback: playback)
                    Color.clear.frame(height: 850)
                }
            }))
            try await host.wait { (host.find(RiveUIView.self)?.bounds.height ?? 0) > 0 }
            let native = try #require(host.find(RiveUIView.self))
            let session = try #require(playback.session)
            let scroll = try #require(host.find(UIScrollView.self))
            #expect(native.isPaused, "No visibility report may start an offscreen illustration")
            let illustration = native.convert(native.bounds, to: scroll)
            let viewportBottom = scroll.bounds.height - scroll.adjustedContentInset.bottom
            for visibleFraction in [0.08, 0.12, 0.08, 0.2] {
                let offset = illustration.minY + illustration.height * visibleFraction - viewportBottom
                scroll.setContentOffset(CGPoint(x: 0, y: max(0, offset)), animated: false)
                try await host.wait { native.isPaused == (visibleFraction < 0.1) }
                #expect(host.find(RiveUIView.self) === native)
                #expect(playback.session === session)
            }
        }

        @Test func sceneAndCoverStopsComposeAndPoppingReleasesTheDestination() async throws {
            let state = LifecycleNavigationState()
            let host = try ViewTestHost()
            defer { host.close() }
            host.show(AnyView(LifecycleNavigationSurface(state: state)))
            state.path = [1]
            try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
            let native = try #require(host.find(RiveUIView.self))
            let timeline = WeakReference(native.rive)
            let file = WeakReference(timeline.value?.file)
            #expect(timeline.value != nil && file.value != nil)

            state.allowed = false
            try await host.wait { native.isPaused }
            host.show(AnyView(LifecycleNavigationSurface(state: state)), phase: .background)
            state.allowed = true
            try await host.wait { native.isPaused }
            state.covered = true
            host.show(AnyView(LifecycleNavigationSurface(state: state)))
            try await host.wait {
                host.controller.presentedViewController != nil && (native.isPaused || native.window == nil)
            }
            state.covered = false
            try await host.wait {
                host.controller.presentedViewController == nil && host.find(RiveUIView.self)?.isPaused == false
            }
            #expect(host.find(RiveUIView.self)?.rive === timeline.value)

            state.path.removeAll()
            try await host.wait { native.rive == nil && timeline.value == nil && file.value == nil }
            state.path = [1]
            try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
            #expect(host.find(RiveUIView.self)?.rive != nil)
        }

        @Test(arguments: [false, true])
        func closingTheOwnerReleasesSessionFileAndNativeView(keyboard: Bool) async throws {
            let host = try ViewTestHost()
            defer { host.close() }
            var owner: IllustrationPlayback? = IllustrationPlayback()
            host.show(AnyView(ScrollView {
                if let owner {
                    switch keyboard {
                    case true: KeyboardIllustration(playback: owner)
                    case false: AboutIllustration(playback: owner)
                    }
                }
            }))
            try await host.wait { host.find(RiveUIView.self)?.isPaused == false }
            let session = WeakReference(owner?.session)
            let native = WeakReference(host.find(RiveUIView.self))
            let timeline = WeakReference(native.value?.rive)
            let file = WeakReference(timeline.value?.file)
            #expect(session.value != nil && native.value != nil && timeline.value != nil && file.value != nil)
            host.show(AnyView(EmptyView()))
            owner = nil
            try await host.wait { session.value == nil && native.value == nil && timeline.value == nil && file.value == nil }
        }

        @Test func anOutstandingDrawableRequestCoalescesAndCannotRestartADetachedView() async throws {
            let resource = try await RiveResource.load(named: "about-story", in: .main)
            let session = try await resource.makeSession(AboutIllustration.contract)
            let host = try ViewTestHost()
            defer { host.close() }
            let log = RivePlaybackLog()
            let prior = RiveLog.logger
            RiveLog.logger = log
            defer { RiveLog.logger = prior }
            host.show(AnyView(RiveCanvas(session: session, paused: true).frame(width: 280, height: 190)))
            try await host.wait { !log.advances.isEmpty }
            let native = try #require(host.find(RiveUIView.self))
            let metal = try #require(host.find(MTKView.self))
            // Let the initial zero-time paint finish before introducing a new
            // request. The following burst holds the main actor, so completion
            // of drawable acquisition cannot be delivered between requests.
            try await Task.sleep(for: .milliseconds(200))
            session.rive.backgroundColor = RiveRuntime.Color(0x02000000)
            try await Task.sleep(for: .milliseconds(100))
            native.isPaused = false
            log.reset()
            for _ in 0..<24 { native.draw(in: metal) }
            #expect(log.advances.count == 1)

            // Invalidate synchronously before yielding to the pending result;
            // the separate owner tests exercise SwiftUI's dismantle path.
            native.isPaused = true
            native.rive = nil
            host.show(AnyView(EmptyView()))
            let detachedCount = log.advances.count
            try await Task.sleep(for: .milliseconds(200))
            #expect(native.isPaused && native.rive == nil)
            #expect(log.advances.count == detachedCount)
        }
    }
}

@MainActor
private final class LifecycleResourceBarrier {
    let cancellation = LifecycleCancellationWitness()
    private var pending: CheckedContinuation<Void, Never>?
    private var holdNext = true
    private(set) var returned = 0
    var isSuspended: Bool { pending != nil }

    func load(_ name: String, _ bundle: Bundle) async throws -> RiveResource {
        let resource = try await RiveResource.load(named: name, in: bundle)
        if holdNext {
            holdNext = false
            let cancellation = cancellation
            await withTaskCancellationHandler {
                await withCheckedContinuation { pending = $0 }
            } onCancel: {
                cancellation.recordCancellation()
            }
        }
        returned += 1
        // Return even after cancellation to exercise the consumer's admission
        // check, rather than allowing a cooperative loader to hide a stale result.
        return resource
    }

    func release() {
        let continuation = pending
        pending = nil
        continuation?.resume()
    }
}

private final class LifecycleCancellationWitness: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var wasCancelled: Bool { lock.withLock { cancelled } }
    func recordCancellation() { lock.withLock { cancelled = true } }
}

@MainActor
@Observable
private final class LifecycleNavigationState {
    var path: [Int] = []
    var covered = false
    var allowed = true
}

@Equatable
private struct LifecycleNavigationSurface: View {
    private let inputRevision = UUID()
    @SkipEquatable let state: LifecycleNavigationState

    var body: some View {
        @Bindable var navigation = state
        NavigationStack(path: $navigation.path) {
            Text("説明画面の入口")
                .navigationDestination(for: Int.self) { _ in
                    ScrollView { AboutIllustration() }
                }
        }
        .environment(\.illustrationPlaybackAllowed, state.allowed && !state.covered)
        .fullScreenCover(isPresented: $navigation.covered) {
            Text("説明画面を覆う別画面")
        }
    }
}
