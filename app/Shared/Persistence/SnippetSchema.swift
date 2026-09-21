import Foundation

/// Versioned domain schema; connection mechanics do not know table layouts.
enum SnippetSchema {
    static func prepare(_ db: SQLiteDatabase, at url: URL) throws {
        let version = try db.rows("PRAGMA user_version", []) { $0.int(0) }.first ?? 0
        guard version <= 2 else { throw StoreError.newerVersion }
        try db.execute("PRAGMA journal_mode=WAL")
        try db.preserveWAL()
        try db.execute("PRAGMA synchronous=FULL")
        try db.writeTransaction {
            // Another process may have migrated while this connection waited for the write lock.
            let current = try db.rows("PRAGMA user_version", []) { $0.int(0) }.first ?? 0
            guard current <= 2 else { throw StoreError.newerVersion }
            if current == 0 {
                try db.execute("CREATE TABLE snippets(id TEXT PRIMARY KEY,title TEXT NOT NULL,body TEXT NOT NULL,search_key TEXT NOT NULL,pinned INTEGER NOT NULL,revision INTEGER NOT NULL,updated REAL NOT NULL,deleted INTEGER NOT NULL,use_count INTEGER NOT NULL DEFAULT 0 CHECK(use_count>=0),last_used REAL)")
                try db.execute("CREATE INDEX IF NOT EXISTS snippets_order ON snippets(deleted,pinned DESC,updated DESC,id)")
                try db.execute("CREATE TABLE drafts(id TEXT PRIMARY KEY,snippet_id TEXT NOT NULL,base_revision INTEGER NOT NULL,title TEXT NOT NULL,body TEXT NOT NULL,sequence INTEGER NOT NULL,updated REAL NOT NULL)")
            }
            if current == 1 {
                try db.execute("ALTER TABLE snippets ADD COLUMN use_count INTEGER NOT NULL DEFAULT 0 CHECK(use_count>=0)")
                try db.execute("ALTER TABLE snippets ADD COLUMN last_used REAL")
            }
            if current < 2 {
                try db.execute("CREATE TABLE snippet_uses(id TEXT PRIMARY KEY,snippet_id TEXT NOT NULL,used REAL NOT NULL)")
                try db.execute("CREATE INDEX snippet_uses_snippet ON snippet_uses(snippet_id)")
                try db.execute("CREATE INDEX snippets_usage_order ON snippets(deleted,use_count DESC,updated DESC,id)")
                try db.execute("CREATE INDEX snippets_pinned_usage_order ON snippets(deleted,pinned,use_count DESC,updated DESC,id)")
                try db.execute("PRAGMA user_version=2")
            }
        }
        // Derived lookup structures shared by app and extension connections.
        try db.execute("CREATE INDEX IF NOT EXISTS drafts_order ON drafts(updated DESC,id)")
        try db.execute("CREATE INDEX IF NOT EXISTS drafts_snippet ON drafts(snippet_id,updated DESC,id)")
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }
}
