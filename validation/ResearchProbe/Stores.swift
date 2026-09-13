// Research-only scratch stores. No production architecture decision is implied.
import Foundation
import SwiftData
import CoreData
import SQLite3

struct ProbeValue: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var body: String
    var revision: Int = 0
}

@Model final class ProbeSnippet {
    @Attribute(.unique) var id: String
    var title: String
    var body: String
    var revision: Int
    init(_ value: ProbeValue) {
        id = value.id; title = value.title; body = value.body; revision = value.revision
    }
    var value: ProbeValue { ProbeValue(id: id, title: title, body: body, revision: revision) }
}

@MainActor
protocol ProbeStore {
    func replace(_ values: [ProbeValue]) throws
    func values() throws -> [ProbeValue]
}

@MainActor
final class SwiftDataProbe: ProbeStore {
    let container: ModelContainer
    let context: ModelContext
    init(url: URL, readOnly: Bool = false) throws {
        let schema = Schema([ProbeSnippet.self])
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: !readOnly, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }
    func replace(_ values: [ProbeValue]) throws {
        let existing = try context.fetch(FetchDescriptor<ProbeSnippet>())
        let next = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        let previousIDs = Set(existing.map(\.id))
        for object in existing {
            if let value = next[object.id] {
                object.title = value.title; object.body = value.body; object.revision = value.revision
            } else { context.delete(object) }
        }
        for value in values where !previousIDs.contains(value.id) { context.insert(ProbeSnippet(value)) }
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func values() throws -> [ProbeValue] {
        try context.fetch(FetchDescriptor<ProbeSnippet>(sortBy: [SortDescriptor(\.id)])).map(\.value)
    }
}

@MainActor
final class CoreDataProbe: ProbeStore {
    let container: NSPersistentContainer
    init(url: URL, readOnly: Bool = false, withTitle: Bool = true) throws {
        let entity = NSEntityDescription()
        entity.name = "Snippet"; entity.managedObjectClassName = "NSManagedObject"
        var fields: [(String, NSAttributeType)] = [("id", .stringAttributeType), ("body", .stringAttributeType), ("revision", .integer64AttributeType)]
        if withTitle { fields.append(("title", .stringAttributeType)) }
        entity.properties = fields.map { name, type in
            let field = NSAttributeDescription(); field.name = name; field.attributeType = type
            field.isOptional = false; field.defaultValue = type == .integer64AttributeType ? 0 : ""
            return field
        }
        let model = NSManagedObjectModel(); model.entities = [entity]
        container = NSPersistentContainer(name: "Scratch", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.isReadOnly = readOnly
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
    }
    func replace(_ values: [ProbeValue]) throws {
        let context = container.viewContext
        for object in try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Snippet")) { context.delete(object) }
        for value in values {
            let object = NSEntityDescription.insertNewObject(forEntityName: "Snippet", into: context)
            object.setValue(value.id, forKey: "id"); object.setValue(value.body, forKey: "body")
            if object.entity.attributesByName["title"] != nil { object.setValue(value.title, forKey: "title") }
            object.setValue(value.revision, forKey: "revision")
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func values() throws -> [ProbeValue] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Snippet")
        request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        return try container.viewContext.fetch(request).map {
            ProbeValue(id: $0.value(forKey: "id") as! String,
                       title: $0.entity.attributesByName["title"] != nil ? $0.value(forKey: "title") as! String : "",
                       body: $0.value(forKey: "body") as! String,
                       revision: ($0.value(forKey: "revision") as! NSNumber).intValue)
        }
    }
    func close() throws {
        container.viewContext.reset()
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }
}

// This handle is deliberately confined to MainActor in the probe; it is not a proposed UI storage design.
@MainActor
final class SQLiteProbe: ProbeStore {
    var db: OpaquePointer?
    init(url: URL, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else { throw error() }
        sqlite3_busy_timeout(db, 100)
        if !readOnly {
            try execute("PRAGMA journal_mode=WAL")
            try execute("CREATE TABLE IF NOT EXISTS snippet(id TEXT PRIMARY KEY,title TEXT NOT NULL,body TEXT NOT NULL,revision INTEGER NOT NULL)")
        }
    }
    isolated deinit { sqlite3_close(db) }
    func error() -> NSError { NSError(domain: "SQLiteProbe", code: Int(sqlite3_errcode(db)), userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]) }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }
    func rows(_ sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw error() }
            result.append((0..<sqlite3_column_count(statement)).map { index in
                sqlite3_column_text(statement, index).map {
                    String(decoding: UnsafeBufferPointer(start: $0, count: Int(sqlite3_column_bytes(statement, index))), as: UTF8.self)
                } ?? ""
            })
        }
        return result
    }
    func replace(_ values: [ProbeValue]) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM snippet")
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT INTO snippet VALUES(?,?,?,?)", -1, &statement, nil) == SQLITE_OK else { throw error() }
            defer { sqlite3_finalize(statement) }
            for value in values {
                for (index,text) in [value.id,value.title,value.body].enumerated() {
                    _ = text.withCString { sqlite3_bind_text(statement, Int32(index+1), $0, Int32(text.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                }
                sqlite3_bind_int(statement,4,Int32(value.revision))
                guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
                sqlite3_reset(statement); sqlite3_clear_bindings(statement)
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func values() throws -> [ProbeValue] {
        try rows("SELECT id,title,body,revision FROM snippet ORDER BY id").map {
            ProbeValue(id: $0[0],title: $0[1],body: $0[2],revision: Int($0[3])!)
        }
    }
}

struct ProbeArchive: Codable {
    let version: Int
    let values: [ProbeValue]
    static func decode(_ data: Data) throws -> [ProbeValue] {
        guard data.count <= 4_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let archive = try JSONDecoder().decode(Self.self, from: data)
        guard archive.version == 1, Set(archive.values.map(\.id)).count == archive.values.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return archive.values
    }
}

@MainActor final class SearchProbe {
    private(set) var generation = 0
    private(set) var ids: [String] = []
    nonisolated static func key(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
    }
    func search(_ query: String, values: [ProbeValue], delay: Duration) async {
        generation += 1; let current = generation
        try? await Task.sleep(for: delay)
        let result = values.filter { Self.key($0.title + "\n" + $0.body).contains(Self.key(query)) }.map(\.id)
        guard current == generation else { return }
        ids = result
    }
}
