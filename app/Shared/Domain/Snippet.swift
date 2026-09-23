import Foundation

enum ProductFeature: Sendable {
    case unlimitedSavedItems, variableReplacement, adFree
}

/// The containing app refreshes this snapshot from verified StoreKit transactions.
enum ProAccess {
    static let freeLimit = 30
    private static let group = "group.nibble.9uiLe.com"
    private static let expirationKey = "pro.entitlementExpiration"

    static func isActive() -> Bool {
        guard let expiration = UserDefaults(suiteName: group)?.object(forKey: expirationKey) as? Date else { return false }
        return expiration > Date()
    }

    static func update(expiration: Date?) {
        let defaults = UserDefaults(suiteName: group)
        if let expiration { defaults?.set(expiration, forKey: expirationKey) }
        else { defaults?.removeObject(forKey: expirationKey) }
    }
}

/// The release policy is shared by the app and its extensions. Changing a feature's
/// audience must not change the stored snippets or the meaning of a verified Pro grant.
enum FeatureAccess {
    static let subscriptionsOffered = false

    static func allows(_ feature: ProductFeature, pro: Bool) -> Bool {
        switch feature {
        case .unlimitedSavedItems, .variableReplacement: true
        case .adFree: pro
        }
    }
}

/// Variable markers live in the original body. Expansion produces a new value only
/// when the user explicitly uses the snippet; it never edits the saved text.
struct SnippetVariables: Sendable, Equatable {
    let body: String
    let names: [String]

    init(_ body: String) {
        self.body = body
        var found: [String] = []
        var seen: Set<String> = []
        var cursor = body.startIndex
        while let start = body.range(of: "{{", range: cursor..<body.endIndex),
              let end = body.range(of: "}}", range: start.upperBound..<body.endIndex) {
            let name = String(body[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
            if Self.valid(name), seen.insert(name).inserted { found.append(name) }
            cursor = end.upperBound
        }
        names = found
    }

    func filled(with values: [String: String]) -> String? {
        guard names.allSatisfy({ values[$0]?.isEmpty == false }) else { return nil }
        var result = ""
        var cursor = body.startIndex
        while let start = body.range(of: "{{", range: cursor..<body.endIndex),
              let end = body.range(of: "}}", range: start.upperBound..<body.endIndex) {
            result += body[cursor..<start.lowerBound]
            let name = String(body[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
            if Self.valid(name), let value = values[name] { result += value }
            else { result += body[start.lowerBound..<end.upperBound] }
            cursor = end.upperBound
        }
        result += body[cursor...]
        return result
    }

    static func valid(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 40 && !name.contains("{") && !name.contains("}")
            && !name.contains("\n") && !name.contains("\r")
    }
}

struct Snippet: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let pinned: Bool
    let revision: Int
    let updatedAt: Date
    let deleted: Bool
    let usage: SnippetUsage
}

struct SnippetSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let preview: String
    let pinned: Bool
    let revision: Int
    /// Keyboard projections deliberately do not read usage (including schema 1).
    let usage: SnippetUsage?

    init(id: UUID, title: String, preview: String, pinned: Bool, revision: Int, usage: SnippetUsage? = nil) {
        self.id = id
        self.title = title
        self.preview = preview
        self.pinned = pinned
        self.revision = revision
        self.usage = usage
    }
}

struct SnippetUsage: Equatable, Sendable {
    static let inactivityDays = 30
    let count: Int
    let lastUsedAt: Date?

    func isDeletionCandidate(at date: Date) -> Bool {
        guard let lastUsedAt else { return false }
        return date.timeIntervalSince(lastUsedAt) >= Double(Self.inactivityDays * 24 * 60 * 60)
    }
}

/// One completed copy, with a stable identity for retrying only its usage record.
struct SnippetUse: Equatable, Sendable {
    let id: UUID
    let snippetID: UUID
    let completedAt: Date
}

enum LibraryFilter: String, CaseIterable, Sendable {
    case all, pinned, drafts, trash

    var ordering: SnippetOrdering { self == .trash ? .recentlyUpdated : .mostUsed }
}

/// Each entry chooses an ordering; storage translates it without sorting loaded bodies.
enum SnippetOrdering {
    case mostUsed, recentlyUpdated, pinnedFirst
}
