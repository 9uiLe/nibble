import Foundation

/// Composition boundary for the app and extension. Each process owns its store;
/// App Group lookup is lazy so an unavailable container becomes a recoverable UI error.
enum SnippetStorage {
    static func sharedContainer() -> SnippetStore {
        SnippetStore(location: {
            guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.nibble.9uiLe.com") else {
                throw StoreError.unavailable
            }
            return group.appending(path: "Library/snippets.sqlite")
        })
    }
}
