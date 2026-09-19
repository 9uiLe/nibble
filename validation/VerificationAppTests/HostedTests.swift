import Testing
import UIKit
@testable import VerificationApp

@Suite("Verification host")
@MainActor
struct HostedTests {
    @Test("The intended Simulator host preserves exact fixture input")
    func hostIdentityAndExactTextTransfer() {
        #expect(Bundle.main.bundleIdentifier == "dev.nibble.VerificationApp")

        let controller = FixtureViewController()
        controller.loadViewIfNeeded()
        let original = "  日本語 か\u{3099}\n\t👩🏽‍💻 <code>  "
        controller.input.text = original
        controller.applyText()
        #expect(Array(controller.output.text!.unicodeScalars) == Array(original.unicodeScalars))
    }
}
