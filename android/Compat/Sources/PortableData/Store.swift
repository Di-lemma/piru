import Foundation
import GRDB

/// The SQLite side of a container. Every model is one row of `portable_models`, its values
/// a JSON object. Each save is one transaction that advances the store's generation and
/// stamps the rows it writes with it; a deleted row leaves a tombstone with the generation
/// that deleted it. A context remembers the generation it has read up to, so the rows and
/// tombstones past it are exactly what other contexts, or other containers, changed since.
final class Store: @unchecked Sendable {
    let queue: DatabaseQueue
    let readOnly: Bool

    /// Tombstones kept per store, in generations. A context that has not read the store in
    /// longer rereads its entities whole.
    static let tombstoneWindow = 4096

    init(url: URL?, readOnly: Bool) throws {
        self.readOnly = readOnly && url != nil
        var configuration = Configuration()
        configuration.readonly = self.readOnly
        if let url {
            if !self.readOnly {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            queue = try DatabaseQueue(path: url.path, configuration: configuration)
        } else {
            queue = try DatabaseQueue(configuration: configuration)
        }
        if !self.readOnly {
            try Self.migrator.migrate(queue)
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("portable_models") { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS portable_models (
                entity TEXT NOT NULL, pk TEXT NOT NULL, data BLOB NOT NULL, PRIMARY KEY (entity, pk)
            ) WITHOUT ROWID
            """)
        }
        migrator.registerMigration("portable_generations") { db in
            try db.execute(sql: """
            ALTER TABLE portable_models ADD COLUMN gen INTEGER NOT NULL DEFAULT 0;
            CREATE INDEX portable_models_gen ON portable_models (gen);
            CREATE TABLE portable_tombstones (
                entity TEXT NOT NULL, pk TEXT NOT NULL, gen INTEGER NOT NULL, PRIMARY KEY (entity, pk)
            ) WITHOUT ROWID;
            CREATE INDEX portable_tombstones_gen ON portable_tombstones (gen);
            CREATE TABLE portable_meta (key TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL) WITHOUT ROWID;
            INSERT INTO portable_meta (key, value) VALUES ('generation', 0), ('tombstone_floor', 0);
            """)
        }
        return migrator
    }

    struct Row {
        let entity: String
        let primaryKey: String
        let data: Data
    }

    /// What changed after a generation: rows written since and rows deleted since. When the
    /// tombstones no longer reach back that far, `rows` is every row of the entities asked
    /// for and `complete` is set, so a row absent from it was deleted.
    struct Changes {
        var generation: Int
        var rows: [Row] = []
        var deleted: [PersistentIdentifier] = []
        var complete = false
    }

    // MARK: Reading

    func read<T>(_ body: (Database) throws -> T) throws -> T {
        try queue.read(body)
    }

    static func generation(_ db: Database) throws -> Int {
        try meta(db, "generation")
    }

    private static func meta(_ db: Database, _ key: String) throws -> Int {
        guard try db.tableExists("portable_meta") else { return 0 }
        return try Int.fetchOne(db, sql: "SELECT value FROM portable_meta WHERE key = ?", arguments: [key]) ?? 0
    }

    static func rows(_ db: Database, entity: String) throws -> [Row] {
        guard try db.tableExists("portable_models") else { return [] }
        return try GRDB.Row.fetchAll(db, sql: "SELECT pk, data FROM portable_models WHERE entity = ?", arguments: [entity])
            .map { Row(entity: entity, primaryKey: $0["pk"], data: $0["data"]) }
    }

    static func row(_ db: Database, _ id: PersistentIdentifier) throws -> Data? {
        try Data.fetchOne(
            db, sql: "SELECT data FROM portable_models WHERE entity = ? AND pk = ?", arguments: [id.entityName, id.primaryKey],
        )
    }

    static func changes(_ db: Database, after generation: Int, entities: Set<String>) throws -> Changes {
        var changes = try Changes(generation: self.generation(db))
        guard changes.generation > generation, !entities.isEmpty else { return changes }
        let names = Array(entities)
        let placeholders = databaseQuestionMarks(count: names.count)
        if try generation < meta(db, "tombstone_floor") {
            changes.complete = true
            changes.rows = try names.flatMap { try rows(db, entity: $0) }
            return changes
        }
        changes.rows = try GRDB.Row.fetchAll(
            db, sql: "SELECT entity, pk, data FROM portable_models WHERE gen > ? AND entity IN (\(placeholders))",
            arguments: StatementArguments([generation] + names),
        ).map { Row(entity: $0["entity"], primaryKey: $0["pk"], data: $0["data"]) }
        changes.deleted = try GRDB.Row.fetchAll(
            db, sql: "SELECT entity, pk FROM portable_tombstones WHERE gen > ? AND entity IN (\(placeholders))",
            arguments: StatementArguments([generation] + names),
        ).map { PersistentIdentifier(entityName: $0["entity"], primaryKey: $0["pk"]) }
        return changes
    }

    /// The primary key and row of a stored model whose `keys` hold the same values as
    /// `fields`, other than `excluding`.
    static func uniqueMatch(
        _ db: Database, entity: String, keys: [String], fields: [String: Data], excluding primaryKey: String,
    ) throws -> (String, Data)? {
        var conditions: [String] = []
        var arguments: [(any DatabaseValueConvertible)?] = [entity, primaryKey]
        for key in keys {
            guard let value = fields[key], let text = String(data: value, encoding: .utf8) else { return nil }
            conditions.append("json_extract(CAST(data AS TEXT), ?) IS json_extract(?, '$')")
            arguments += [jsonPath(key), text]
        }
        let row = try GRDB.Row.fetchOne(
            db,
            sql: "SELECT pk, data FROM portable_models WHERE entity = ? AND pk != ? AND \(conditions.joined(separator: " AND ")) LIMIT 1",
            arguments: StatementArguments(arguments),
        )
        return row.map { ($0["pk"], $0["data"]) }
    }

    private static func jsonPath(_ key: String) -> String {
        "$.\"" + key.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: Writing

    /// Opens the transaction a save runs in and advances the generation it stamps.
    func write<T>(_ body: (Database, Int) throws -> T) throws -> T {
        guard !readOnly else { throw PortableDataError.readOnly }
        return try queue.write { db in
            let generation = try Self.generation(db) + 1
            let result = try body(db, generation)
            try db.execute(sql: "UPDATE portable_meta SET value = ? WHERE key = 'generation'", arguments: [generation])
            let floor = generation - Self.tombstoneWindow
            if floor > 0, generation % 256 == 0 {
                try db.execute(sql: "DELETE FROM portable_tombstones WHERE gen <= ?", arguments: [floor])
                try db.execute(sql: "UPDATE portable_meta SET value = ? WHERE key = 'tombstone_floor'", arguments: [floor])
            }
            return result
        }
    }

    static func put(_ db: Database, _ id: PersistentIdentifier, _ data: Data, generation: Int) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO portable_models (entity, pk, data, gen) VALUES (?, ?, ?, ?)",
            arguments: [id.entityName, id.primaryKey, data, generation],
        )
        try db.execute(
            sql: "DELETE FROM portable_tombstones WHERE entity = ? AND pk = ?", arguments: [id.entityName, id.primaryKey],
        )
    }

    static func remove(_ db: Database, _ id: PersistentIdentifier, generation: Int) throws {
        try db.execute(
            sql: "DELETE FROM portable_models WHERE entity = ? AND pk = ?", arguments: [id.entityName, id.primaryKey],
        )
        try db.execute(
            sql: "INSERT OR REPLACE INTO portable_tombstones (entity, pk, gen) VALUES (?, ?, ?)",
            arguments: [id.entityName, id.primaryKey, generation],
        )
    }
}
