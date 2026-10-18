import Foundation
import UniformTypeIdentifiers

@MainActor
struct SharedDraftLoader {
    let store: any LibraryOpening
    func load(from providers: [NSItemProvider]) async throws -> Draft {
        try Task.checkCancellation()
        let types = [UTType.plainText.identifier, UTType.url.identifier]
        guard let provider = providers.first(where: { candidate in types.contains { candidate.hasItemConformingToTypeIdentifier($0) } }),
              let type = types.first(where: provider.hasItemConformingToTypeIdentifier) else { throw ShareError.unsupported }
        let content: String = try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error { continuation.resume(throwing: error); return }
                switch item {
                case let text as String: continuation.resume(returning: text)
                case let url as URL: continuation.resume(returning: url.absoluteString)
                case let data as Data:
                    guard let text = String(data: data, encoding: .utf8) else { continuation.resume(throwing: ShareError.unsupported); return }
                    continuation.resume(returning: text)
                default: continuation.resume(throwing: ShareError.unsupported)
                }
            }
        }
        try Task.checkCancellation()
        try SnippetText.validate(title: "", body: content)
        let draft = try await store.beginDraft(target: .new, body: content)
        try Task.checkCancellation()
        return draft
    }
}
