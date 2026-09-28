import Foundation

/// A class `@Model` has made storable. The underscored requirements are the macro's; app
/// code reaches a model through ``persistentModelID`` and ``modelContext``, as with SwiftData.
///
/// Refines `SendableMetatype`, as SwiftData's does, and `@Model` declares the conformance
/// on the class itself: that is what keeps a model out of `-default-isolation MainActor`,
/// so its key paths are `Sendable` and `#Predicate` and `SortDescriptor` accept them.
public protocol PersistentModel: AnyObject, Hashable, SendableMetatype {
    var _$backing: ModelBacking { get }
    init(_$snapshot: Snapshot) throws
    func _$encode(into snapshot: inout Snapshot)
    func _$resolve(_ resolver: RelationshipResolver) throws
}

public extension PersistentModel {
    static var _$entityName: String {
        String(describing: Self.self)
    }

    /// Assigned when the model is inserted; a model never inserted has a provisional one.
    var persistentModelID: PersistentIdentifier {
        _$backing.identifier ?? PersistentIdentifier(
            entityName: Self._$entityName, primaryKey: "provisional-\(ObjectIdentifier(self).hashValue)",
        )
    }

    var modelContext: ModelContext? {
        _$backing.context
    }

    var isDeleted: Bool {
        _$backing.isDeleted
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

/// What a model knows about its place in a store.
public final class ModelBacking: @unchecked Sendable {
    public var identifier: PersistentIdentifier?
    weak var context: ModelContext?
    var isDeleted = false

    public init() {}
}

/// One model's stored form: every attribute as a JSON value, every to-one relationship as
/// the primary key it points at.
public struct Snapshot {
    public let identifier: PersistentIdentifier
    var stored: [String: Any]
    var written: [String: Data] = [:]
    var referenced: [any PersistentModel] = []

    init(identifier: PersistentIdentifier, json: Data) throws {
        self.identifier = identifier
        stored = try JSONSerialization.jsonObject(with: json) as? [String: Any] ?? [:]
    }

    init(identifier: PersistentIdentifier) {
        self.identifier = identifier
        stored = [:]
    }

    // MARK: Reading

    public func decode<T: Decodable>(_ key: String) throws -> T {
        let value = stored[key] ?? NSNull()
        let fragment = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        return try JSONDecoder().decode(T.self, from: fragment)
    }

    /// Relationships start empty; ``RelationshipResolver`` fills them once every model
    /// they could point at exists.
    public func decode<M: PersistentModel>(_: String) throws -> M? {
        nil
    }

    public func decode<M: PersistentModel>(_: String) throws -> [M]? {
        nil
    }

    public func decode<M: PersistentModel>(_: String) throws -> [M] {
        []
    }

    func primaryKey(_ key: String) -> String? {
        stored[key] as? String
    }

    func primaryKeys(_ key: String) -> [String] {
        stored[key] as? [String] ?? []
    }

    // MARK: Writing

    public mutating func encode(_ value: some Encodable, _ key: String) {
        written[key] = (try? JSONEncoder().encode(value)) ?? Data("null".utf8)
    }

    public mutating func encode(_ value: (some PersistentModel)?, _ key: String) {
        guard let value, !value.isDeleted else {
            written[key] = Data("null".utf8)
            return
        }
        referenced.append(value)
        written[key] = pendingKey(of: value)
    }

    public mutating func encode(_ value: [some PersistentModel]?, _ key: String) {
        let live = (value ?? []).filter { !$0.isDeleted }
        referenced.append(contentsOf: live as [any PersistentModel])
        let keys = live.map(\.persistentModelID.primaryKey)
        written[key] = (try? JSONEncoder().encode(keys)) ?? Data("[]".utf8)
    }

    /// The target's key as a JSON string. The context assigns identity to every referenced
    /// model before it encodes anything, so this is never provisional in a saved row.
    private func pendingKey(of model: some PersistentModel) -> Data {
        (try? JSONEncoder().encode(model.persistentModelID.primaryKey)) ?? Data("null".utf8)
    }

    var json: Data {
        var out = Data("{".utf8)
        for (index, (key, value)) in written.sorted(by: { $0.key < $1.key }).enumerated() {
            if index > 0 { out.append(Data(",".utf8)) }
            out.append((try? JSONEncoder().encode(key)) ?? Data())
            out.append(Data(":".utf8))
            out.append(value)
        }
        out.append(Data("}".utf8))
        return out
    }
}

/// Reconnects a loaded model's relationships. Forward relationships resolve from the keys
/// the model stored; a to-many side declared with `inverse:` is rebuilt from the models
/// pointing back at it, so the two sides cannot disagree on disk.
public struct RelationshipResolver {
    enum Phase { case forward, inverse }

    let context: ModelContext
    let snapshot: Snapshot?
    let phase: Phase

    public func resolve(_: inout some Decodable, _: String) throws {}

    public func resolve<M: PersistentModel>(_ value: inout M?, _ key: String) throws {
        guard phase == .forward, let snapshot else { return }
        value = try snapshot.primaryKey(key).flatMap { try context.registered(M.self, primaryKey: $0) }
    }

    public func resolve<M: PersistentModel>(_ value: inout [M]?, _ key: String) throws {
        guard phase == .forward, let snapshot else { return }
        value = try snapshot.primaryKeys(key).compactMap { try context.registered(M.self, primaryKey: $0) }
    }

    public func resolve<M: PersistentModel>(_ value: inout [M], _ key: String) throws {
        guard phase == .forward, let snapshot else { return }
        value = try snapshot.primaryKeys(key).compactMap { try context.registered(M.self, primaryKey: $0) }
    }

    public func resolveInverse<M: PersistentModel, Owner: PersistentModel>(
        _ value: inout [M]?, _ inverse: KeyPath<M, Owner?>, owner: Owner,
    ) throws {
        guard phase == .inverse else { return }
        value = context.registeredModels(M.self).filter { $0[keyPath: inverse] === owner }
    }

    public func resolveInverse<M: PersistentModel, Owner: PersistentModel>(
        _ value: inout [M], _ inverse: KeyPath<M, Owner?>, owner: Owner,
    ) throws {
        guard phase == .inverse else { return }
        value = context.registeredModels(M.self).filter { $0[keyPath: inverse] === owner }
    }
}
