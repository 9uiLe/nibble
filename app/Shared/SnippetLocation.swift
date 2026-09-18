import Foundation

enum SnippetLocation {
    static func database() throws -> URL {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.nibble.9uiLe.com") else {
            throw StoreError.unavailable
        }
        return group.appending(path: "Library/snippets.sqlite")
    }
}
