import Foundation
import Testing
@testable import Nibble

@Suite("Rebuilt interface boundaries")
struct RebuiltInterfaceTests {
    @Test func anotherHostPermanentlyEndsTheQualification() {
        let host = UUID()
        var lease = KeyboardInputLease(document: host)
        lease.observe(document: UUID())
        lease.observe(document: host)
        #expect(!lease.isValid && lease.destinationDocument == nil)
    }

    @Test func changingSelectionWithinTheSameDocumentEndsTheQualification() {
        let host = UUID()
        var lease = KeyboardInputLease(document: host)
        lease.invalidate()
        lease.observe(document: host)
        #expect(!lease.isValid && lease.destinationDocument == nil)
    }

    @Test func observingTheSameHostWithoutAnExternalEventKeepsTheQualification() {
        let host = UUID()
        var lease = KeyboardInputLease(document: host)
        lease.observe(document: host)
        lease.observe(document: host)
        #expect(lease.isValid && lease.destinationDocument == host)
    }

    @Test func aTemporarilyMissingDocumentCannotBecomeQualifiedAgain() {
        let host = UUID()
        var lease = KeyboardInputLease(document: host)
        lease.observe(document: nil)
        lease.observe(document: host)
        #expect(!lease.isValid && lease.destinationDocument == nil)
    }
}
