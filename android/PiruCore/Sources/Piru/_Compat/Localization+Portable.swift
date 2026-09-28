#if !canImport(Darwin)
    import Foundation

    public nonisolated struct LocalizedStringResource: ExpressibleByStringInterpolation, Hashable, Sendable,
        CustomStringConvertible {
        public struct StringInterpolation: StringInterpolationProtocol, Sendable {
            var key = ""
            var arguments: [String] = []

            public init(literalCapacity: Int, interpolationCount: Int) {
                key.reserveCapacity(literalCapacity + interpolationCount * 3)
            }

            public mutating func appendLiteral(_ literal: String) {
                key += literal.replacingOccurrences(of: "%", with: "%%")
            }

            public mutating func appendInterpolation(_ value: some BinaryInteger) {
                key += "%lld"
                arguments.append(String(value))
            }

            public mutating func appendInterpolation(_ value: some BinaryFloatingPoint) {
                key += "%lf"
                arguments.append(String(describing: Double(value)))
            }

            public mutating func appendInterpolation(_ value: LocalizedStringResource) {
                key += "%@"
                arguments.append(String(localized: value))
            }

            public mutating func appendInterpolation(_ value: some Any) {
                key += "%@"
                arguments.append(String(describing: value))
            }
        }

        public let key: String
        let arguments: [String]

        public init(stringLiteral value: String) {
            key = value
            arguments = []
        }

        public init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key
            arguments = stringInterpolation.arguments
        }

        public init(_ key: String, defaultValue _: String? = nil, comment _: StaticString? = nil) {
            self.key = key
            arguments = []
        }

        public var description: String {
            String(localized: self)
        }
    }

    public nonisolated extension String {
        typealias LocalizationValue = LocalizedStringResource

        init(localized resource: LocalizedStringResource, comment _: StaticString? = nil) {
            self = LocalizationCatalog.shared.resolve(resource)
        }

        init(localized key: String, defaultValue _: String? = nil, comment _: StaticString? = nil) {
            self = LocalizationCatalog.shared.resolve(LocalizedStringResource(stringLiteral: key))
        }
    }

    /// The app's string catalog, read from the same `Localizable.xcstrings` the iOS build
    /// compiles. Until ``load(xcstrings:)`` runs, every string resolves to its English key.
    public final nonisolated class LocalizationCatalog: @unchecked Sendable {
        public static let shared = LocalizationCatalog()

        private let lock = NSLock()
        private var strings: [String: [String: String]] = [:]
        private var language = "en"

        /// Reads the catalog and picks the best of its languages for `preferred`.
        public func load(xcstrings url: URL, preferred: [String] = Locale.preferredLanguages) throws {
            let catalog = try JSONDecoder().decode(XCStrings.self, from: Data(contentsOf: url))
            var table: [String: [String: String]] = [:]
            for (key, entry) in catalog.strings {
                for (language, localization) in entry.localizations ?? [:] {
                    if let value = localization.stringUnit?.value {
                        table[key, default: [:]][language] = value
                    }
                }
            }
            let available = Set(table.values.flatMap(\.keys))
            let chosen = preferred.lazy.compactMap { Self.match($0, in: available) }.first ?? "en"
            lock.withLock {
                strings = table
                language = chosen
            }
        }

        func resolve(_ resource: LocalizedStringResource) -> String {
            let format = lock.withLock { strings[resource.key]?[language] } ?? resource.key
            return Self.substitute(format, resource.arguments)
        }

        /// `zh-Hans-CN` → `zh-Hans`, `es-MX` → `es`: the longest catalog language that prefixes it.
        private static func match(_ tag: String, in available: Set<String>) -> String? {
            var parts = tag.split(separator: "-").map(String.init)
            while !parts.isEmpty {
                let candidate = parts.joined(separator: "-")
                if available.contains(candidate) { return candidate }
                parts.removeLast()
            }
            return nil
        }

        /// Replaces `%@`, `%lld`, `%lf`, `%d` and their positional `%1$@` forms with the
        /// already-formatted arguments, and `%%` with `%`.
        private static func substitute(_ format: String, _ arguments: [String]) -> String {
            guard format.contains("%") else { return format }
            let pattern = /%(?:(\d+)\$)?(?:@|lld|ld|lf|d|f|%)/
            var next = 0
            return format.replacing(pattern) { match in
                if match.output.0 == "%%" { return "%" }
                let index: Int
                if let position = match.output.1, let n = Int(position) {
                    index = n - 1
                } else {
                    index = next
                    next += 1
                }
                return arguments.indices.contains(index) ? arguments[index] : ""
            }
        }
    }

    private nonisolated struct XCStrings: Decodable {
        struct Entry: Decodable {
            let localizations: [String: Localization]?
        }

        struct Localization: Decodable {
            let stringUnit: StringUnit?
        }

        struct StringUnit: Decodable {
            let value: String
        }

        let strings: [String: Entry]
    }
#endif
