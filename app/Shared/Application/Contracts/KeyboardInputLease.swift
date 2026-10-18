import Foundation

/// Value entry edits a local buffer while the external host keeps first responder.
/// Any host transition or selection callback permanently ends this qualification.
struct KeyboardInputLease: Equatable, Sendable {
    private let originalDocument: UUID
    private(set) var isValid = true

    init(document: UUID) { originalDocument = document }

    var destinationDocument: UUID? { isValid ? originalDocument : nil }

    mutating func observe(document: UUID?) {
        if document != originalDocument { invalidate() }
    }

    mutating func invalidate() { isValid = false }
}
