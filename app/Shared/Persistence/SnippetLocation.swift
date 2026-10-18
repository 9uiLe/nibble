import Foundation

enum SnippetLocation {
    static func database() throws -> URL {
        let files = FileManager.default
        guard let container = files.containerURL(forSecurityApplicationGroupIdentifier: "group.nibble.9uiLe.com") else {
            throw StoreError.unavailable
        }
        return container.appending(path: "Library").appending(path: "snippets.sqlite")
    }
}
