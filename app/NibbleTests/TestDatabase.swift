import Foundation
@testable import Nibble

struct TestDatabase {
    let url: URL
    let store: SnippetStore

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nibble-contract-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        url = root.appending(path: "snippets.sqlite")
        store = SnippetStore(location: url)
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

func create(_ store: SnippetStore, title: String = "", body: String) async throws -> UUID {
    var input = try await store.beginDraft()
    input.title = title
    input.body = body
    return try await store.save(input)
}

func testVariableName(_ source: String) -> VariableName {
    guard let parsed = VariableName(source) else { preconditionFailure("The fixture must use a valid marker name") }
    return parsed
}

func testVariableValues(_ entries: [String: String]) -> [VariableName: String] {
    entries.reduce(into: [:]) { result, entry in result[testVariableName(entry.key)] = entry.value }
}

@MainActor
final class RecordingLibraryEffects: LibraryEffects {
    enum Event: Equatable {
        case copy(String)
        case announce(String)
    }
    private(set) var events: [Event] = []

    func copy(_ text: String) { events += [.copy(text)] }
    func announce(_ notice: LibraryModel.Notice) { events += [.announce(notice.announcement)] }
}

extension LibraryModel {
    convenience init(store: SnippetStore, surface: LibrarySurface = .library, libraryReader: (any LibraryReading)? = nil) {
        self.init(store: store, effects: RecordingLibraryEffects(), surface: surface, libraryReader: libraryReader)
    }
}
