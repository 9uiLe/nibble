import Foundation
import SQLite3

enum SQLValue {
    case text(String)
    case int(Int)
    case real(Double)
}

/// A connection belongs to one actor. Leased statements leave the idle pool, so
/// nested queries can never reset a statement whose row is still being decoded.
final class SQLiteDatabase {
    enum Access { case readWrite, readOnly, readWriteExisting }
    private struct IdleStatement {
        let sql: String
        let pointer: OpaquePointer
    }

    private let handle: OpaquePointer
    private var idle: [IdleStatement] = []
    private let capacity = 32
    var changes: Int { Int(sqlite3_changes(handle)) }

    init(url: URL, access: Access = .readWrite) throws {
        let mode: Int32
        switch access {
        case .readOnly: mode = SQLITE_OPEN_READONLY
        case .readWriteExisting: mode = SQLITE_OPEN_READWRITE
        case .readWrite: mode = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        }
        var candidate: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &candidate, mode | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let candidate else {
            sqlite3_close_v2(candidate)
            throw StoreError.database
        }
        handle = candidate
        sqlite3_busy_timeout(candidate, 2_000)
    }

    deinit {
        idle.forEach { sqlite3_finalize($0.pointer) }
        sqlite3_close_v2(handle)
    }

    func preserveWAL() throws {
        var persist: Int32 = 1
        guard sqlite3_file_control(handle, "main", SQLITE_FCNTL_PERSIST_WAL, &persist) == SQLITE_OK else {
            throw StoreError.database
        }
    }

    func readTransaction<Result>(_ operation: () throws -> Result) throws -> Result {
        try performTransaction(writing: false, operation)
    }

    func writeTransaction<Result>(_ operation: () throws -> Result) throws -> Result {
        try performTransaction(writing: true, operation)
    }

    private func performTransaction<Result>(writing: Bool, _ operation: () throws -> Result) throws -> Result {
        try execute(writing ? "BEGIN IMMEDIATE" : "BEGIN")
        do {
            let result = try operation()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func execute(_ sql: String, _ arguments: [SQLValue] = []) throws {
        try withStatement(sql, arguments) { statement in
            while try advance(statement) { }
        }
    }

    func rows<Result>(_ sql: String, _ arguments: [SQLValue], map: (SQLRow) throws -> Result) throws -> [Result] {
        try withStatement(sql, arguments) { statement in
            var results: [Result] = []
            while try advance(statement) {
                results.append(try map(SQLRow(statement: statement)))
            }
            return results
        }
    }

    private func advance(_ statement: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: true
        case SQLITE_DONE: false
        default: throw StoreError.database
        }
    }

    private func lease(_ sql: String) throws -> OpaquePointer {
        if let index = idle.lastIndex(where: { $0.sql == sql }) {
            return idle.remove(at: index).pointer
        }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw StoreError.database
        }
        return statement
    }

    private func withStatement<Result>(_ sql: String, _ arguments: [SQLValue], _ operation: (OpaquePointer) throws -> Result) throws -> Result {
        let statement = try lease(sql)
        do {
            try bind(arguments, to: statement)
            let result = try operation(statement)
            guard sqlite3_reset(statement) == SQLITE_OK, sqlite3_clear_bindings(statement) == SQLITE_OK else {
                throw StoreError.database
            }
            if let duplicate = idle.firstIndex(where: { $0.sql == sql }) {
                sqlite3_finalize(idle.remove(at: duplicate).pointer)
            }
            if idle.count >= capacity { sqlite3_finalize(idle.removeFirst().pointer) }
            idle.append(IdleStatement(sql: sql, pointer: statement))
            return result
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
    }

    private func bind(_ arguments: [SQLValue], to statement: OpaquePointer) throws {
        guard Int(sqlite3_bind_parameter_count(statement)) == arguments.count else { throw StoreError.database }
        for (offset, argument) in arguments.enumerated() {
            let column = Int32(offset + 1)
            let status: Int32
            switch argument {
            case .int(let value): status = sqlite3_bind_int64(statement, column, Int64(value))
            case .real(let value): status = sqlite3_bind_double(statement, column, value)
            case .text(let value):
                status = value.utf8CString.withUnsafeBufferPointer { buffer in
                    sqlite3_bind_text(statement, column, buffer.baseAddress, Int32(buffer.count - 1),
                                      unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            }
            guard status == SQLITE_OK else { throw StoreError.database }
        }
    }
}

struct SQLRow {
    let statement: OpaquePointer

    func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(statement, column) == SQLITE_NULL
    }

    func text(_ column: Int32) throws -> String {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT else { throw StoreError.database }
        let length = Int(sqlite3_column_bytes(statement, column))
        guard length > 0 else { return "" }
        guard let pointer = sqlite3_column_text(statement, column),
              let decoded = String(bytes: UnsafeBufferPointer(start: pointer, count: length), encoding: .utf8) else {
            throw StoreError.database
        }
        return decoded
    }

    func int(_ column: Int32) throws -> Int {
        guard sqlite3_column_type(statement, column) == SQLITE_INTEGER,
              let decoded = Int(exactly: sqlite3_column_int64(statement, column)) else { throw StoreError.database }
        return decoded
    }

    func bool(_ column: Int32) throws -> Bool {
        switch try int(column) {
        case 0: false
        case 1: true
        default: throw StoreError.database
        }
    }

    func uuid(_ column: Int32) throws -> UUID {
        guard let identifier = UUID(uuidString: try text(column)) else { throw StoreError.database }
        return identifier
    }

    func double(_ column: Int32) throws -> Double {
        let kind = sqlite3_column_type(statement, column)
        guard kind == SQLITE_INTEGER || kind == SQLITE_FLOAT else { throw StoreError.database }
        let decoded = sqlite3_column_double(statement, column)
        guard decoded.isFinite else { throw StoreError.database }
        return decoded
    }
}
