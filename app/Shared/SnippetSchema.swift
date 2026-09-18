import Foundation

/// Versioned domain schema; connection mechanics do not know table layouts.
enum SnippetSchema {
    static func prepare(_ db: SQLiteDatabase, at url: URL) throws {
        let version = try db.rows("PRAGMA user_version", []) { $0.int(0) }.first ?? 0
        guard version <= 1 else { throw StoreError.newerVersion }
        try db.execute("PRAGMA journal_mode=WAL")
        try db.preserveWAL()
        try db.execute("PRAGMA synchronous=FULL")
        if version == 0 {
            try db.writeTransaction {
                try db.execute("CREATE TABLE IF NOT EXISTS snippets(id TEXT PRIMARY KEY,title TEXT NOT NULL,body TEXT NOT NULL,search_key TEXT NOT NULL,pinned INTEGER NOT NULL,revision INTEGER NOT NULL,updated REAL NOT NULL,deleted INTEGER NOT NULL)")
                try db.execute("CREATE INDEX IF NOT EXISTS snippets_order ON snippets(deleted,pinned DESC,updated DESC,id)")
                try db.execute("CREATE TABLE IF NOT EXISTS drafts(id TEXT PRIMARY KEY,snippet_id TEXT NOT NULL,base_revision INTEGER NOT NULL,title TEXT NOT NULL,body TEXT NOT NULL,sequence INTEGER NOT NULL,updated REAL NOT NULL)")
                try db.execute("PRAGMA user_version=1")
            }
        }
        // Derived lookup structure; safe for every version-1 database and shared connection.
        try db.execute("CREATE INDEX IF NOT EXISTS drafts_order ON drafts(updated DESC,id)")
        try db.execute("CREATE INDEX IF NOT EXISTS drafts_snippet ON drafts(snippet_id,updated DESC,id)")
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }
}
