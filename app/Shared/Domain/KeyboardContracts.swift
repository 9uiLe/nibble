import Foundation

enum KeyboardFilter: String, CaseIterable, Sendable {
    case all, pinned
    var title: String { self == .all ? "すべて" : "ピン留め" }
}

struct KeyboardRequest: Hashable, Sendable {
    static let pageSize = 50
    let filter: KeyboardFilter
    let offset: Int

    init(filter: KeyboardFilter = .all, offset: Int = 0) {
        self.filter = filter
        self.offset = min(max(0, offset), Int.max - Self.pageSize - 1)
    }
}

struct KeyboardPage: Equatable, Sendable {
    let items: [SnippetSummary]
    let hasMore: Bool
}

protocol KeyboardReading: Sendable {
    func page(_ request: KeyboardRequest) async throws -> KeyboardPage
    func body(for item: SnippetSummary) async throws -> String
    func setPinned(_ pinned: Bool, for item: SnippetSummary) async throws -> SnippetSummary
}

enum KeyboardReadError: Error, LocalizedError {
    case notPrepared, changed

    var errorDescription: String? {
        switch self {
        case .notPrepared: "nibbleで文章やURLを保存してから、更新ボタンを押してください。"
        case .changed: "項目が変更されています。一覧を更新して選び直してください。"
        }
    }
}
