import Testing
import UIKit
@testable import VerificationApp

@Suite("Verification host")
@MainActor
struct HostedTests {
    @Test("Tests execute inside the intended Simulator app")
    func hostIdentity() {
        #expect(Bundle.main.bundleIdentifier == "dev.nibble.VerificationApp")
        #expect(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26)
    }

    @Test("The fixture preserves Unicode scalars and whitespace")
    func exactTextTransfer() {
        let controller = FixtureViewController()
        controller.loadViewIfNeeded()
        let original = "  日本語 か\u{3099}\n\t👩🏽‍💻 <code>  "
        controller.input.text = original
        controller.applyText()
        #expect(Array(controller.output.text!.unicodeScalars) == Array(original.unicodeScalars))
    }
}
