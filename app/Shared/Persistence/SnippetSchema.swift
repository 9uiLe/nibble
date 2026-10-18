import Foundation

enum SnippetSchema {
    private static func admittedVersion(_ database: SQLiteDatabase) throws -> Int {
        guard let number = try database.rows("PRAGMA user_version", [], map: { try $0.int(0) }).first,
              number >= 0 else { throw StoreError.database }
        guard number <= 2 else { throw StoreError.newerVersion }
        if number == 0 {
            let objects = try database.rows("SELECT name FROM sqlite_schema WHERE lower(name) NOT GLOB 'sqlite_*' LIMIT 1", []) {
                try $0.text(0)
            }
            guard objects.isEmpty else { throw StoreError.database }
        }
        return number
    }

    static func prepare(_ database: SQLiteDatabase, at location: URL) throws {
        // An unversioned file is ours only when its schema is empty. Inspect a
        // consistent snapshot before changing any connection or file settings.
        try database.readTransaction { _ = try admittedVersion(database) }
        try database.execute("PRAGMA synchronous = FULL")
        try database.writeTransaction {
            // Read again after obtaining the cross-process write reservation.
            let existing = try admittedVersion(database)
            if existing == 0 { try installInitialTables(database) }
            if existing == 1 {
                try database.execute("ALTER TABLE snippets ADD COLUMN use_count INTEGER NOT NULL DEFAULT 0 CHECK(use_count>=0)")
                try database.execute("ALTER TABLE snippets ADD COLUMN last_used REAL")
            }
            if existing < 2 {
                try database.execute("CREATE TABLE snippet_uses(id TEXT PRIMARY KEY,snippet_id TEXT NOT NULL,used REAL NOT NULL)")
                try database.execute("CREATE INDEX snippet_uses_snippet ON snippet_uses(snippet_id)")
                try database.execute("PRAGMA user_version = 2")
            }
            for statement in indexes { try database.execute(statement) }
        }
        // WAL changes the file header. Do it only after admission under the
        // write reservation, so a racing foreign schema cannot be converted.
        let modes = try database.rows("PRAGMA journal_mode = WAL", []) { try $0.text(0) }
        guard modes.first == "wal" else { throw StoreError.database }
        try database.preserveWAL()
        if !["-wal", "-shm"].allSatisfy({ FileManager.default.fileExists(atPath: location.path + $0) }) {
            // Switching modes does not itself materialize the files a directory-
            // read-only keyboard needs. Commit the unchanged version through
            // WAL once, after admission and persistence have both succeeded.
            try database.writeTransaction {
                guard try admittedVersion(database) == 2 else { throw StoreError.database }
                try database.execute("PRAGMA user_version = 2")
            }
        }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: location.path)
    }

    private static func installInitialTables(_ database: SQLiteDatabase) throws {
        try database.execute("""
            CREATE TABLE snippets(
                id TEXT PRIMARY KEY,title TEXT NOT NULL,body TEXT NOT NULL,search_key TEXT NOT NULL,
                pinned INTEGER NOT NULL,revision INTEGER NOT NULL,updated REAL NOT NULL,deleted INTEGER NOT NULL,
                use_count INTEGER NOT NULL DEFAULT 0 CHECK(use_count>=0),last_used REAL)
            """)
        try database.execute("""
            CREATE TABLE drafts(
                id TEXT PRIMARY KEY,snippet_id TEXT NOT NULL,base_revision INTEGER NOT NULL,
                title TEXT NOT NULL,body TEXT NOT NULL,sequence INTEGER NOT NULL,updated REAL NOT NULL)
            """)
    }

    private static let indexes = [
        "CREATE INDEX IF NOT EXISTS snippets_order ON snippets(deleted,pinned DESC,updated DESC,id)",
        "CREATE INDEX IF NOT EXISTS snippets_usage_order ON snippets(deleted,use_count DESC,updated DESC,id)",
        "CREATE INDEX IF NOT EXISTS snippets_pinned_usage_order ON snippets(deleted,pinned,use_count DESC,updated DESC,id)",
        "CREATE INDEX IF NOT EXISTS drafts_order ON drafts(updated DESC,id)",
        "CREATE INDEX IF NOT EXISTS drafts_snippet ON drafts(snippet_id,updated DESC,id)"
    ]
}
