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
