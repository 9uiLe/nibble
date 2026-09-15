import Foundation
@testable import Nibble

struct TestDatabase {
    let url: URL
    let store: SnippetStore

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "NibbleTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "snippets.sqlite")
        store = SnippetStore(location: url)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

func create(_ store: SnippetStore, title: String = "", body: String) async throws -> UUID {
    var draft = try await store.beginDraft(body: body)
    draft.title = title
    return try await store.save(draft)
}

