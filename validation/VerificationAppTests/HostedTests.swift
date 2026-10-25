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
        let original = "  日本語 か\u{3099}\r\n\t👩🏽‍💻\0 <code>  "
        controller.input.text = original
        controller.applyText()
        #expect(Array((controller.output.text ?? "").utf8) == Array(original.utf8))
        #expect(Array((controller.output.accessibilityValue ?? "").utf8) == Array(original.utf8))
    }

    @Test("Observing one destination does not alter the other input or observation")
    func independentDestinationsAndObservations() {
        let controller = FixtureViewController()
        controller.loadViewIfNeeded()
        let first = "か\u{3099}\nA"
        let second = "が\tB 👩🏽‍💻"
        controller.input.text = first
        controller.secondInput.text = second

        controller.applyText()
        #expect(Array((controller.input.text ?? "").utf8) == Array(first.utf8))
        #expect(Array((controller.secondInput.text ?? "").utf8) == Array(second.utf8))
        #expect(controller.secondOutput.accessibilityValue == "未実行")
        #expect(controller.secondOutputBytes.accessibilityValue == "未実行")

        controller.applySecondText()
        #expect(Array((controller.output.accessibilityValue ?? "").utf8) == Array(first.utf8))
        #expect(Array((controller.secondOutput.accessibilityValue ?? "").utf8) == Array(second.utf8))

        controller.input.text = "A を訂正"
        controller.applyText()
        #expect(Array((controller.secondInput.text ?? "").utf8) == Array(second.utf8))
        #expect(Array((controller.secondOutput.accessibilityValue ?? "").utf8) == Array(second.utf8))
    }

    @Test("Visible UTF-8 observations distinguish combining text and preserve control bytes")
    func exactVisibleByteObservations() {
        let controller = FixtureViewController()
        controller.loadViewIfNeeded()
        controller.input.text = "\0\r\nか\u{3099}"
        controller.secondInput.text = "が"
        controller.applyText()
        controller.applySecondText()
        #expect(controller.outputBytes.text == "[0,13,10,227,129,139,227,130,153]")
        #expect(controller.outputBytes.accessibilityValue == controller.outputBytes.text)
        #expect(controller.secondOutputBytes.text == "[227,129,140]")
        #expect(controller.secondOutputBytes.accessibilityValue == controller.secondOutputBytes.text)
    }

    @Test("Reset clears both destinations and their previous observations")
    func resetBothDestinations() {
        let controller = FixtureViewController()
        controller.loadViewIfNeeded()
        controller.input.text = "A"
        controller.secondInput.text = "B"
        controller.applyText()
        controller.applySecondText()
        controller.reset()
        #expect(controller.input.text.isEmpty)
        #expect(controller.secondInput.text.isEmpty)
        for output in [controller.output, controller.outputBytes, controller.secondOutput, controller.secondOutputBytes] {
            #expect(output.text == "未実行")
            #expect(output.accessibilityValue == "未実行")
        }
    }
}
