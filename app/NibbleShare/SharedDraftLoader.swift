import Foundation
import UniformTypeIdentifiers

/// Preserves the provider's original text and waits for the shared draft to persist.
@MainActor
struct SharedDraftLoader {
    let store: any LibraryOpening

    func load(from providers: [NSItemProvider]) async throws -> Draft {
        try Task.checkCancellation()
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) else { throw ShareError.unsupported }
        let body = try await Self.read(provider)
        try Task.checkCancellation()
        try SnippetText.validate(title: "", body: body)
        return try await store.beginDraft(snippetID: nil, body: body)
    }

    private static func read(_ provider: NSItemProvider) async throws -> String {
        let type = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) ? UTType.plainText.identifier : UTType.url.identifier
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else if let text = item as? String { continuation.resume(returning: text) }
                else if let url = item as? URL { continuation.resume(returning: url.absoluteString) }
                else if let data = item as? Data, let text = String(data: data, encoding: .utf8) { continuation.resume(returning: text) }
                else { continuation.resume(throwing: ShareError.unsupported) }
            }
        }
    }
}
