import Foundation
import UniformTypeIdentifiers

enum IncomingTextError: Error { case unsupported, tooLarge, multipleItems }

@MainActor
enum IncomingTextLoader {
    static func load(_ providers: [NSItemProvider]) async throws -> String {
        let types = [UTType.plainText.identifier, UTType.url.identifier]
        let supported = providers.filter { provider in types.contains(where: provider.hasItemConformingToTypeIdentifier) }
        guard supported.count <= 1 else { throw IncomingTextError.multipleItems }
        guard let provider = supported.first,
              let type = types.first(where: provider.hasItemConformingToTypeIdentifier) else { throw IncomingTextError.unsupported }
        try Task.checkCancellation()
        let text: String = try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error { continuation.resume(throwing: error); return }
                switch item {
                case let text as String: continuation.resume(returning: text)
                case let url as URL: continuation.resume(returning: url.absoluteString)
                case let data as Data:
                    guard let text = String(data: data, encoding: .utf8) else {
                        continuation.resume(throwing: IncomingTextError.unsupported)
                        return
                    }
                    continuation.resume(returning: text)
                default: continuation.resume(throwing: IncomingTextError.unsupported)
                }
            }
        }
        try Task.checkCancellation()
        guard text.utf8.count <= 1_048_576 else { throw IncomingTextError.tooLarge }
        return text
    }
}
