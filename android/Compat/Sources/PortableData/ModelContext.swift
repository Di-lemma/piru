import Foundation
import GRDB

/// A container: one SQLite file (or an in-memory database) holding every model as a row.
public final class ModelContainer: @unchecked Sendable {
    public let schema: Schema
    public let configurations: [ModelConfiguration]
    let database: DatabaseQueue
    private nonisolated(unsafe) var main: ModelContext?

    public init(for schema: Schema, configurations: [ModelConfiguration]) throws {
        self.schema = schema
        self.configurations = configurations
        if let url = configurations.first?.url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            database = try DatabaseQueue(path: url.path)
        } else {
            database = try DatabaseQueue()
        }
        try database.write { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS portable_models (
                entity TEXT NOT NULL, pk TEXT NOT NULL, data BLOB NOT NULL, PRIMARY KEY (entity, pk)
            ) WITHOUT ROWID
            """)
        }
    }

    public convenience init(for schema: Schema, configurations: ModelConfiguration...) throws {
        try self.init(for: schema, configurations: configurations)
    }

    public convenience init(for types: any PersistentModel.Type..., configurations: ModelConfiguration...) throws {
        try self.init(for: Schema(types), configurations: configurations)
    }

    /// The container the app's views read, set by `.modelContainer(_:)`; `@Query` and the
    /// `modelContext` environment default to its main context.
    public nonisolated(unsafe) static var application: ModelContainer?

    @MainActor
    public var mainContext: ModelContext {
        if let main { return main }
        let context = ModelContext(self)
        main = context
        return context
    }
}

public struct FetchDescriptor<T: PersistentModel> {
    public var predicate: Predicate<T>?
    public var sortBy: [SortDescriptor<T>]
    public var fetchLimit: Int?
    public var fetchOffset: Int?
    public var includePendingChanges = true
    public var propertiesToFetch: [PartialKeyPath<T>] = []
    public var relationshipKeyPathsForPrefetching: [PartialKeyPath<T>] = []

    public init(predicate: Predicate<T>? = nil, sortBy: [SortDescriptor<T>] = []) {
        self.predicate = predicate
        self.sortBy = sortBy
    }
}

public enum PortableDataError: Error {
    case notInContainer(String)
}

/// A working set of models over a container. Each entity is read whole on first use and
/// held in an identity map, so every fetch after that is a filter over objects already
/// in memory — the shape of a personal journal, where the whole log is a few thousand rows.
/// `@unchecked Sendable` as SwiftData's is used: one context lives on one actor, and the
/// environment value that carries the main context needs a Sendable default.
public final class ModelContext: @unchecked Sendable {
    public let container: ModelContainer
    public var autosaveEnabled = true

    /// Called after every insert, delete and save. A UI layer hangs its invalidation here, in
    /// whichever Observation its views track (Skip's, on Android).
    public var changeHandler: (() -> Void)?

    private func changed() {
        changeHandler?()
    }

    private var registry: [PersistentIdentifier: any PersistentModel] = [:]
    private var byEntity: [String: [PersistentIdentifier]] = [:]
    private var loaded: Set<String> = []
    private var deleted: [PersistentIdentifier: any PersistentModel] = [:]
    private var loadDepth = 0
    private var resolvingInverses = false

    public init(_ container: ModelContainer) {
        self.container = container
    }

    /// Edits to a model's properties are not observed, so any registered model counts as
    /// possibly changed and a save always writes the whole working set.
    public var hasChanges: Bool {
        !registry.isEmpty || !deleted.isEmpty
    }

    // MARK: Changes

    public func insert<T: PersistentModel>(_ model: T) {
        guard model._$backing.context !== self else { return }
        let id = model._$backing.identifier
            ?? PersistentIdentifier(entityName: T._$entityName, primaryKey: UUID().uuidString)
        model._$backing.identifier = id
        model._$backing.context = self
        model._$backing.isDeleted = false
        register(model, id)
        changed()
    }

    public func delete(_ model: some PersistentModel) {
        let id = model.persistentModelID
        model._$backing.isDeleted = true
        registry[id] = nil
        byEntity[id.entityName]?.removeAll { $0 == id }
        deleted[id] = model
        changed()
    }

    public func delete<T: PersistentModel>(model: T.Type, where predicate: Predicate<T>? = nil) throws {
        for model in try fetch(FetchDescriptor(predicate: predicate)) {
            delete(model)
        }
    }

    public func rollback() {
        registry.removeAll()
        byEntity.removeAll()
        loaded.removeAll()
        deleted.removeAll()
    }

    /// Writes every live model and removes every deleted one. Models a saved model points
    /// at are inserted first, as SwiftData does, so no row refers to an unsaved one; that
    /// happens in its own pass, because a row can only name a model that has its identity.
    public func save() throws {
        var pending = Array(registry.values)
        while let model = pending.popLast() {
            var probe = Snapshot(identifier: model.persistentModelID)
            model._$encode(into: &probe)
            for target in probe.referenced where target._$backing.context !== self {
                adopt(target)
                pending.append(target)
            }
        }
        let rows = registry.values.map { model in
            var snapshot = Snapshot(identifier: model.persistentModelID)
            model._$encode(into: &snapshot)
            return (snapshot.identifier, snapshot.json)
        }
        let removed = Array(deleted.keys)
        try container.database.write { db in
            for (id, json) in rows {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO portable_models (entity, pk, data) VALUES (?, ?, ?)",
                    arguments: [id.entityName, id.primaryKey, json],
                )
            }
            for id in removed {
                try db.execute(
                    sql: "DELETE FROM portable_models WHERE entity = ? AND pk = ?",
                    arguments: [id.entityName, id.primaryKey],
                )
            }
        }
        deleted.removeAll()
        try resolveInverses()
        changed()
    }

    private func adopt(_ model: any PersistentModel) {
        func open(_ model: some PersistentModel) { insert(model) }
        open(model)
    }

    // MARK: Reads

    public func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        var results = try all(T.self)
        if let predicate = descriptor.predicate {
            results = try results.filter { try predicate.evaluate($0) }
        }
        if !descriptor.sortBy.isEmpty {
            results.sort(using: descriptor.sortBy)
        }
        let start = min(descriptor.fetchOffset ?? 0, results.count)
        let end = descriptor.fetchLimit.map { min(start + $0, results.count) } ?? results.count
        return Array(results[start ..< end])
    }

    public func fetchCount(_ descriptor: FetchDescriptor<some PersistentModel>) throws -> Int {
        try fetch(descriptor).count
    }

    public func fetchIdentifiers(_ descriptor: FetchDescriptor<some PersistentModel>) throws -> [PersistentIdentifier] {
        try fetch(descriptor).map(\.persistentModelID)
    }

    public func model(for identifier: PersistentIdentifier) -> any PersistentModel {
        registry[identifier]!
    }

    public func registeredModel<T: PersistentModel>(for identifier: PersistentIdentifier) -> T? {
        registry[identifier] as? T
    }

    func registered<T: PersistentModel>(_: T.Type, primaryKey: String) throws -> T? {
        try ensureLoaded(T.self)
        return registry[PersistentIdentifier(entityName: T._$entityName, primaryKey: primaryKey)] as? T
    }

    func all<T: PersistentModel>(_: T.Type) throws -> [T] {
        try ensureLoaded(T.self)
        return (byEntity[T._$entityName] ?? []).compactMap { registry[$0] as? T }
    }

    // MARK: Loading

    private func register(_ model: some PersistentModel, _ id: PersistentIdentifier) {
        if registry.updateValue(model, forKey: id) == nil {
            byEntity[id.entityName, default: []].append(id)
        }
    }

    /// Reads every row of `T` the first time `T` is asked for. Forward relationships
    /// resolve as each entity arrives; inverse sides wait until the outermost load has
    /// finished, because the models they are rebuilt from may still be arriving.
    private func ensureLoaded<T: PersistentModel>(_: T.Type) throws {
        let name = T._$entityName
        guard loaded.insert(name).inserted else { return }
        loadDepth += 1
        defer { loadDepth -= 1 }
        let rows = try container.database.read { db in
            try Row.fetchAll(db, sql: "SELECT pk, data FROM portable_models WHERE entity = ?", arguments: [name])
        }
        var arrived: [(T, Snapshot)] = []
        for row in rows {
            let id = PersistentIdentifier(entityName: name, primaryKey: row["pk"])
            guard registry[id] == nil, deleted[id] == nil else { continue }
            let snapshot = try Snapshot(identifier: id, json: row["data"])
            let model = try T(_$snapshot: snapshot)
            model._$backing.context = self
            register(model, id)
            arrived.append((model, snapshot))
        }
        for (model, snapshot) in arrived {
            try model._$resolve(RelationshipResolver(context: self, snapshot: snapshot, phase: .forward))
        }
        if loadDepth == 1 {
            try resolveInverses()
        }
    }

    /// Rebuilds every derived to-many side. It loads the whole schema first and then works
    /// only in memory: the pass holds `inout` access to each side it writes, so nothing
    /// inside it may load, since a load would resolve inverses again and touch that side.
    private func resolveInverses() throws {
        guard !resolvingInverses else { return }
        resolvingInverses = true
        defer { resolvingInverses = false }
        for type in container.schema.types {
            try load(type)
        }
        let resolver = RelationshipResolver(context: self, snapshot: nil, phase: .inverse)
        for model in Array(registry.values) {
            try model._$resolve(resolver)
        }
    }

    private func load(_ type: any PersistentModel.Type) throws {
        func open<T: PersistentModel>(_: T.Type) throws { try ensureLoaded(T.self) }
        try open(type)
    }

    func registeredModels<T: PersistentModel>(_: T.Type) -> [T] {
        (byEntity[T._$entityName] ?? []).compactMap { registry[$0] as? T }
    }
}
