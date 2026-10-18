import Foundation
import RivePresentation
import RiveRuntime
import SwiftUI
import Testing
import UIKit
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Rebuilt Rive boundary", .serialized)
    @MainActor struct RivePresentationTests {
        @Test func realAssetsHaveIndependentBindings() async throws {
            for (name, contract) in [("about-story", AboutIllustration.contract),
                                     ("keyboard-story", KeyboardIllustration.contract)] {
                let resource = try await RiveResource.load(named: name, in: .main)
                let first = try await resource.makeSession(contract)
                let second = try await resource.makeSession(contract)
                #expect(first.rive !== second.rive)
                #expect(first.data !== second.data)
                first.data.setValue(of: BoolProperty(path: "motionAllowed"), to: false)
                second.data.setValue(of: BoolProperty(path: "motionAllowed"), to: true)
                #expect(try await first.data.value(of: BoolProperty(path: "motionAllowed")) == false)
                #expect(try await second.data.value(of: BoolProperty(path: "motionAllowed")) == true)
            }
        }

        @Test func wrongPropertyRejectsSession() async throws {
            let resource = try await RiveResource.load(named: "about-story", in: .main)
            let good = AboutIllustration.contract
            let wrong = RiveContract(artboard: good.artboard, stateMachine: good.stateMachine,
                                     viewModel: good.viewModel, properties: ["doesNotExist": .boolean])
            do {
                _ = try await resource.makeSession(wrong)
                Issue.record("A missing property must reject the asset contract")
            } catch RiveContractError.property(let model, let name) {
                #expect(model == good.viewModel && name == "doesNotExist")
            }
        }

        @Test func canvasComposesStopsAndReleasesItsNativeReference() async throws {
            let resource = try await RiveResource.load(named: "about-story", in: .main)
            let session = try await resource.makeSession(AboutIllustration.contract)
            let host = try ViewTestHost()
            defer { host.close() }
            let log = RivePlaybackLog()
            let previous = RiveLog.logger
            RiveLog.logger = log
            defer { RiveLog.logger = previous }
            host.show(AnyView(RiveCanvas(session: session).frame(width: 300, height: 200)))
            try await host.wait { log.advances.contains { $0.delta > 0 } }
            let native = try #require(host.find(RiveUIView.self))
            host.show(AnyView(RiveCanvas(session: session, paused: true).frame(width: 300, height: 200)))
            try await host.wait { native.isPaused }
            try await Task.sleep(for: .milliseconds(150))
            let stopped = log.advances.count
            try await Task.sleep(for: .milliseconds(150))
            #expect(log.advances.count == stopped)
            host.show(AnyView(RiveCanvas(session: session).frame(width: 300, height: 200)), phase: .background)
            try await Task.sleep(for: .milliseconds(100))
            #expect(native.isPaused)
            #expect(log.advances.count == stopped)
            host.show(AnyView(RiveCanvas(session: session).frame(width: 300, height: 200)))
            try await host.wait { log.advances.count > stopped }
            #expect(log.advances[stopped].delta == 0)
            #expect(host.find(RiveUIView.self) === native)
            host.show(AnyView(EmptyView()))
            try await host.wait { native.isPaused && native.rive == nil }
        }

        @Test func pausedPaletteRebuildRetainsSessionWithoutAdvancingTime() async throws {
            let resource = try await RiveResource.load(named: "about-story", in: .main)
            let session = try await resource.makeSession(AboutIllustration.contract)
            let host = try ViewTestHost()
            defer { host.close() }
            let log = RivePlaybackLog()
            let previous = RiveLog.logger
            RiveLog.logger = log
            defer { RiveLog.logger = previous }
            host.show(AnyView(RiveCanvas(session: session, paused: true).frame(width: 300, height: 200)))
            try await host.wait { host.find(RiveUIView.self) != nil }
            let old = try #require(host.find(RiveUIView.self))
            session.data.setValue(of: ColorProperty(path: "paper"), to: RiveRuntime.Color(0xFF25282C))
            try await Task.sleep(for: .milliseconds(100))
            log.reset()
            host.show(AnyView(RiveCanvas(session: session, paused: true, renderingRevision: 1)
                .frame(width: 300, height: 200)))
            try await host.wait { host.find(RiveUIView.self) !== old && !log.advances.isEmpty }
            let current = try #require(host.find(RiveUIView.self))
            #expect(current.rive === session.rive && current.isPaused)
            #expect(old.isPaused && old.rive == nil)
            #expect(log.advances.allSatisfy { $0.delta == 0 })
            #expect(try await session.data.value(of: ColorProperty(path: "paper")).argbValue == 0xFF25282C)
        }
    }
}
