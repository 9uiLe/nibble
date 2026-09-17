import Foundation
import RivePresentation
import RiveRuntime
import Testing
@testable import Nibble

extension UIIntegrationTests {
    @Test @MainActor
    func riveContractAndIndependentSessions() async throws {
        let resource = try await RiveResource.load(named: "about-story", in: .main)
        let first = try await resource.makeSession(AboutIllustration.contract)
        let second = try await resource.makeSession(AboutIllustration.contract)
        #expect(first.rive.file === second.rive.file)
        #expect(first.rive.artboard !== second.rive.artboard)
        #expect(first.rive.stateMachine !== second.rive.stateMachine)
        #expect(first.data !== second.data)
        first.data.setValue(of: BoolProperty(path: "motionAllowed"), to: false)
        first.rive.stateMachine.advance(by: 1.0 / 60)
        #expect(try await first.data.value(of: BoolProperty(path: "motionAllowed")) == false)
        #expect(try await first.data.value(of: BoolProperty(path: "active")) == false)
        #expect(try await second.data.value(of: BoolProperty(path: "motionAllowed")))
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

    @Test @MainActor
    func riveStoryKeepsPlayingAndHonorsMotionPreference() async throws {
        let resource = try await RiveResource.load(named: "about-story", in: .main)
        let session = try await resource.makeSession(AboutIllustration.contract)
        let active = BoolProperty(path: "active")
        session.rive.stateMachine.advance(by: 1.0 / 60)
        #expect(try await session.data.value(of: active))
        // More than two complete 6.2-second cycles must not enter the static state.
        for _ in 0..<800 { session.rive.stateMachine.advance(by: 1.0 / 60) }
        #expect(try await session.data.value(of: active))
        session.data.setValue(of: BoolProperty(path: "motionAllowed"), to: false)
        session.rive.stateMachine.advance(by: 1.0 / 60)
        #expect(try await session.data.value(of: active) == false)
        for _ in 0..<400 { session.rive.stateMachine.advance(by: 1.0 / 60) }
        #expect(try await session.data.value(of: active) == false)
        session.data.setValue(of: BoolProperty(path: "motionAllowed"), to: true)
        session.rive.stateMachine.advance(by: 1.0 / 60)
        #expect(try await session.data.value(of: active))
    }

    @Test @MainActor
    func missingRiveResourceIsAnError() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await RiveResource.load(named: "missing-animation", in: .main)
        }
    }
}
