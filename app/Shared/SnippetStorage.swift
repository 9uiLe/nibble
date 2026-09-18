import Foundation

/// Composition boundary for the app and extension. Each process owns its store;
/// App Group lookup is lazy so an unavailable container becomes a recoverable UI error.
enum SnippetStorage {
    static func sharedContainer() -> SnippetStore {
        SnippetStore(location: SnippetLocation.database)
    }
}
