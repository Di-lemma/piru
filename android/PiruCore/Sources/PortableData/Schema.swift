import Foundation

/// The model types a container stores.
public final class Schema: @unchecked Sendable {
    public struct Version: Sendable, Hashable {
        public let major: Int, minor: Int, patch: Int

        public init(_ major: Int, _ minor: Int, _ patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }
    }

    public enum Attribute {
        public struct Option: Sendable, Hashable {
            let name: String

            public static let unique = Option(name: "unique")
            public static let externalStorage = Option(name: "externalStorage")
            public static let allowsCloudEncryption = Option(name: "allowsCloudEncryption")
            public static let preserveValueOnDeletion = Option(name: "preserveValueOnDeletion")
            public static let ephemeral = Option(name: "ephemeral")
            public static let spotlight = Option(name: "spotlight")
        }
    }

    public enum Relationship {
        public enum DeleteRule: Sendable, Hashable {
            case nullify
            case cascade
            case deny
            case noAction
        }

        public struct Option: Sendable, Hashable {
            let name: String

            public static let unique = Option(name: "unique")
        }
    }

    public let types: [any PersistentModel.Type]
    public let version: Version

    public init(_ types: [any PersistentModel.Type], version: Version = Version(1, 0, 0)) {
        self.types = types
        self.version = version
    }

    public convenience init(_ types: any PersistentModel.Type..., version: Version = Version(1, 0, 0)) {
        self.init(types, version: version)
    }
}

/// Where and how a container keeps its store.
public struct ModelConfiguration: Sendable, Hashable {
    public struct CloudKitDatabase: Sendable, Hashable {
        let name: String

        public static let automatic = CloudKitDatabase(name: "automatic")
        public static let none = CloudKitDatabase(name: "none")

        public static func `private`(_ container: String) -> CloudKitDatabase {
            CloudKitDatabase(name: container)
        }
    }

    public let url: URL?
    public let isStoredInMemoryOnly: Bool
    public let allowsSave: Bool

    public init(
        _ name: String? = nil,
        isStoredInMemoryOnly: Bool = false,
        allowsSave: Bool = true,
        cloudKitDatabase _: CloudKitDatabase = .automatic,
    ) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        url = isStoredInMemoryOnly ? nil : support.appending(path: "\(name ?? "default").store")
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        self.allowsSave = allowsSave
    }

    public init(
        _: String? = nil,
        url: URL,
        allowsSave: Bool = true,
        cloudKitDatabase _: CloudKitDatabase = .automatic,
    ) {
        self.url = url
        isStoredInMemoryOnly = false
        self.allowsSave = allowsSave
    }
}

/// A model's identity in its store: stable across launches, unlike its object identity.
public struct PersistentIdentifier: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let entityName: String
    public let primaryKey: String

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.entityName, lhs.primaryKey) < (rhs.entityName, rhs.primaryKey)
    }

    public var description: String {
        "\(entityName)/\(primaryKey)"
    }
}
