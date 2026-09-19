import Foundation
import SQLite3

enum SQLValue {
    case text(String), int(Int), real(Double)
}

/// Non-Sendable handle owner, confined to a store or reader actor; no pointer escapes.
final class SQLiteDatabase {
    enum Access { case readWrite, readOnly, readWriteExisting }
    private let handle: OpaquePointer
    private var statements: [String: OpaquePointer] = [:]
    private var recency: [String] = []
    private let statementLimit = 32
    var changes: Int { Int(sqlite3_changes(handle)) }

    init(url: URL, access: Access = .readWrite) throws {
        var opened: OpaquePointer?
        let flags: Int32 = switch access {
        case .readOnly: SQLITE_OPEN_READONLY
        case .readWrite: SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
        case .readWriteExisting: SQLITE_OPEN_READWRITE
        }
        guard sqlite3_open_v2(url.path, &opened, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let opened else {
            if let opened { sqlite3_close_v2(opened) }
            throw StoreError.database
        }
        handle = opened
        sqlite3_busy_timeout(handle, 2_000)
    }

    /// Readers without directory write access need the WAL and shared index to remain available.
    func preserveWAL() throws {
        var enabled: Int32 = 1
        guard sqlite3_file_control(handle, "main", SQLITE_FCNTL_PERSIST_WAL, &enabled) == SQLITE_OK else {
            throw StoreError.database
        }
    }

    deinit {
        for statement in statements.values { sqlite3_finalize(statement) }
        sqlite3_close_v2(handle)
    }

    func readTransaction<T>(_ work: () throws -> T) throws -> T {
        try performTransaction("BEGIN", work)
    }

    func writeTransaction<T>(_ work: () throws -> T) throws -> T {
        try performTransaction("BEGIN IMMEDIATE", work)
    }

    private func performTransaction<T>(_ begin: String, _ work: () throws -> T) throws -> T {
        try execute(begin)
        do {
            let result = try work()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func execute(_ sql: String, _ values: [SQLValue] = []) throws {
        try withStatement(sql, values) { statement in
            while try step(statement) { }
        }
    }

    func rows<T>(_ sql: String, _ values: [SQLValue], map: (SQLRow) throws -> T) throws -> [T] {
        try withStatement(sql, values) { statement in
            var output: [T] = []
            while try step(statement) { output.append(try map(SQLRow(statement: statement))) }
            return output
        }
    }

    private func step(_ statement: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw StoreError.database
        }
    }

    /// A lease removes the statement from the cache, including for nested reads of the same SQL.
    /// Reset and clear every binding before reuse so large/sensitive text is not retained.
    private func withStatement<T>(_ sql: String, _ values: [SQLValue], _ work: (OpaquePointer) throws -> T) throws -> T {
        let statement: OpaquePointer
        if let cached = statements.removeValue(forKey: sql) {
            recency.removeAll { $0 == sql }
            statement = cached
        } else {
            var prepared: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else {
                if let prepared { sqlite3_finalize(prepared) }
                throw StoreError.database
            }
            statement = prepared
        }
        do {
            guard sqlite3_bind_parameter_count(statement) == values.count else { throw StoreError.database }
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                let result: Int32
                switch value {
                case .text(let text):
                    result = text.utf8CString.withUnsafeBufferPointer {
                        sqlite3_bind_text(statement, index, $0.baseAddress, Int32($0.count - 1), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    }
                case .int(let number): result = sqlite3_bind_int64(statement, index, Int64(number))
                case .real(let number): result = sqlite3_bind_double(statement, index, number)
                }
                guard result == SQLITE_OK else { throw StoreError.database }
            }
            let result = try work(statement)
            guard sqlite3_reset(statement) == SQLITE_OK,
                  sqlite3_clear_bindings(statement) == SQLITE_OK else { throw StoreError.database }
            // Reentrant use can leave another idle statement for the same SQL.
            if let previous = statements.removeValue(forKey: sql) { sqlite3_finalize(previous) }
            recency.removeAll { $0 == sql }
            if recency.count == statementLimit, let oldest = statements.removeValue(forKey: recency.removeFirst()) {
                sqlite3_finalize(oldest)
            }
            statements[sql] = statement
            recency.append(sql)
            return result
        } catch {
            // Failed statements are finalized, never returned to the pool.
            sqlite3_finalize(statement)
            throw error
        }
    }
}

struct SQLRow {
    let statement: OpaquePointer
    func uuid(_ column: Int32) throws -> UUID {
        guard let value = UUID(uuidString: text(column)) else { throw StoreError.database }
        return value
    }
    func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func text(_ column: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, column) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
    }
}
