// Simulator subprocess for controlled SQLite crash/locking experiments.
import Foundation
import SQLite3
import Darwin

func fail(_ db: OpaquePointer?) -> Never {
    fputs(String(cString: sqlite3_errmsg(db)) + "\n", stderr); exit(1)
}
let path = CommandLine.arguments[1], operation = CommandLine.arguments[2]
var db: OpaquePointer?
let flags = operation == "readonly" ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else { fail(db) }
sqlite3_busy_timeout(db, 100)
@MainActor func execute(_ sql: String) {
    if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { fail(db) }
}
@MainActor func value() -> String {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT body FROM snippet WHERE id=1", -1, &statement, nil) == SQLITE_OK,
          sqlite3_step(statement) == SQLITE_ROW else { fail(db) }
    defer { sqlite3_finalize(statement) }
    return String(cString: sqlite3_column_text(statement, 0))
}
func ready() {
    print("READY \(getpid())"); fflush(stdout)
    _ = readLine()
}
switch operation {
case "setup":
    execute("PRAGMA journal_mode=WAL; CREATE TABLE snippet(id INTEGER PRIMARY KEY,body TEXT); INSERT INTO snippet VALUES(1,'original')")
case "read", "readonly": print(value())
case "environment": print(ProcessInfo.processInfo.operatingSystemVersionString + "; SQLite " + String(cString: sqlite3_libversion()))
case "checkpoint": execute("PRAGMA wal_checkpoint(TRUNCATE)")
case "write": execute("BEGIN IMMEDIATE; UPDATE snippet SET body='committed' WHERE id=1; COMMIT")
case "hold-write":
    execute("BEGIN IMMEDIATE; UPDATE snippet SET body='uncommitted' WHERE id=1")
    ready(); execute("ROLLBACK")
case "hold-read":
    execute("BEGIN"); print(value()); ready(); print(value()); execute("COMMIT"); print(value())
case "integrity":
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK,
          sqlite3_step(statement) == SQLITE_ROW else { fail(db) }
    print(String(cString: sqlite3_column_text(statement, 0))); sqlite3_finalize(statement)
default: exit(2)
}
sqlite3_close(db)
