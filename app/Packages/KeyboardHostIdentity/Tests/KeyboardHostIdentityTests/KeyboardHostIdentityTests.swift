import Foundation
import KeyboardHostIdentity
import KeyboardHostIdentityFixtures
import Testing

@Suite("Public keyboard host identity boundary")
@MainActor
struct KeyboardHostIdentityTests {
    @Test(arguments: [false, true])
    func theSwiftImportPreservesAnUnavailableIdentifierAsNil(unavailable: Bool) {
        let document = UUID()
        let controller = NibbleIdentityTestController(document: unavailable ? nil : document)

        let identifier: UUID? = NibbleKeyboardDocumentIdentifier(controller)

        #expect(identifier == (unavailable ? nil : document))
        #expect(controller.fixtureProxy.documentReadCount == 1)
        #expect(controller.fixtureProxy.contextReadCount == 0)
        #expect(controller.fixtureProxy.insertedTexts.isEmpty)
    }

    @Test
    func anUnavailableProxyNeverReachesAdmissionOrInsertion() {
        let document = UUID()
        let controller = NibbleIdentityTestController(document: document)
        controller.proxyUnavailable = true
        let identifier: UUID? = NibbleKeyboardDocumentIdentifier(controller)
        var admissions = 0

        let inserted = NibbleKeyboardInsertText(controller, "送らない本文", document) {
            admissions += 1
            return true
        }

        #expect(identifier == nil)
        #expect(!inserted && admissions == 0)
        #expect(controller.fixtureProxy.documentReadCount == 0)
        #expect(controller.fixtureProxy.contextReadCount == 0)
        #expect(controller.fixtureProxy.insertedTexts.isEmpty)
        #expect(controller.fixtureProxy.unexpectedMutationCount == 0)
    }

    @Test(arguments: [false, true])
    func aMissingOrDifferentDocumentCannotInsert(unavailable: Bool) {
        let expected = UUID()
        let controller = NibbleIdentityTestController(document: unavailable ? nil : UUID())
        var admissions = 0

        let inserted = NibbleKeyboardInsertText(controller, "別文書へ送らない", expected) {
            admissions += 1
            return true
        }

        #expect(!inserted && admissions == 0)
        #expect(controller.fixtureProxy.documentReadCount == 1)
        #expect(controller.fixtureProxy.contextReadCount == 0)
        #expect(controller.fixtureProxy.insertedTexts.isEmpty)
        #expect(controller.fixtureProxy.unexpectedMutationCount == 0)
    }

    @Test(arguments: [false, true])
    func admissionMustStillHoldAfterTheDocumentGetter(reenters: Bool) {
        let document = UUID()
        let controller = NibbleIdentityTestController(document: document)
        controller.admissionAllowed = reenters
        controller.invalidatesAdmissionDuringDocumentRead = reenters
        var admissions = 0

        let inserted = NibbleKeyboardInsertText(controller, "失効後は送らない", document) {
            admissions += 1
            return controller.admissionAllowed
        }

        #expect(!inserted && admissions == 1)
        #expect(controller.admissionInvalidationCount == (reenters ? 1 : 0))
        #expect(controller.fixtureProxy.documentReadCount == 1)
        #expect(controller.fixtureProxy.contextReadCount == 0)
        #expect(controller.fixtureProxy.insertedTexts.isEmpty)
        #expect(controller.fixtureProxy.unexpectedMutationCount == 0)
    }

    @Test
    func aQualifiedDocumentReceivesOneInsertWithTheOriginalBytes() throws {
        let document = UUID()
        let controller = NibbleIdentityTestController(document: document)
        let original = " \tか\u{3099}\r\n\0👩🏽‍💻 "
        var admissions = 0

        let inserted = NibbleKeyboardInsertText(controller, original, document) {
            admissions += 1
            return controller.admissionAllowed
        }

        #expect(inserted && admissions == 1)
        #expect(controller.fixtureProxy.insertedTexts.count == 1)
        let received = try #require(controller.fixtureProxy.insertedTexts.first)
        #expect(received.utf8.elementsEqual(original.utf8))
        #expect(controller.fixtureProxy.documentReadCount == 1)
        #expect(controller.fixtureProxy.contextReadCount == 0)
        #expect(controller.fixtureProxy.unexpectedMutationCount == 0)
    }
}
