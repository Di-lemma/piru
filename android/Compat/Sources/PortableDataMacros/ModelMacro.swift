import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Model`: makes a class storable and observable, as SwiftData's does.
///
/// Storable: a backing that holds its store identity, an initializer that rebuilds it from a
/// stored snapshot, a restore pass that writes stored values back into a live instance, an
/// encoder, and a description of its relationships, unique attributes and renamed keys.
///
/// Observable: each stored `var` becomes a tracked property (``PersistedPropertyMacro``)
/// whose accessors report reads and writes to the model's registrar, as `@Observable`'s do,
/// and report every write to the model's context, which is how the context knows what to
/// save and when to autosave, and how a relationship's inverse side follows an assignment.
///
/// The generated code names every stored property and lets the property's declared type
/// pick the overload: a `Codable` value is stored as itself, a model or an array of
/// models as the identifiers it points at. That is what lets the macro work from syntax
/// alone, without knowing which of the class's types are models.
///
/// A property's initializer is its value for a row stored before the property existed,
/// as SwiftData's lightweight migration reads it. `@Attribute(originalName:)` names the key
/// an older row stored it under.
public struct ModelMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        guard let className = declaration.as(ClassDeclSyntax.self)?.name.trimmedDescription else { return [] }
        let properties = storedProperties(of: declaration)
        let stored = properties.filter { $0.derivedFrom == nil }
        let decode = properties.map { "self.\($0.name) = try snapshot.decode(\($0.decodeArguments))" }
        let restore = stored.map { property in
            "try snapshot.restore(\\\(className).\(property.name), on: self, \(property.decodeArguments), keys: keys)"
        }
        let encode = stored.map { "try snapshot.encode(self.\($0.name), \"\($0.name)\")" }
        var describe = stored.map { property in
            "entity.property(\"\(property.name)\", \\\(className).\(property.name), deleteRule: \(property.deleteRule))"
        }
        describe += properties.compactMap { property in
            property.derivedFrom.map {
                "entity.inverse(\"\(property.name)\", \\\(className).\(property.name), \($0), deleteRule: \(property.deleteRule))"
            }
        }
        describe += stored.compactMap { property in
            property.originalName.map { "entity.rename(\"\(property.name)\", from: \($0))" }
        }
        describe += (stored.filter(\.isUnique).map { [$0.name] } + uniqueConstraints(of: declaration))
            .map { "entity.unique([\($0.map { "\"\($0)\"" }.joined(separator: ", "))])" }
        if properties.contains(where: { $0.isMutable && !$0.isTracked }) {
            describe.append("entity.tracksMutations = false")
        }
        return [
            "public let _$backing = PortableData.ModelBacking()",
            "public let _$observationRegistrar = PortableData.ModelObservationRegistrar()",
            """
            public init(_$snapshot snapshot: PortableData.Snapshot) throws {
            \(raw: decode.joined(separator: "\n"))
            _$backing.identifier = snapshot.identifier
            }
            """,
            """
            public func _$restore(from snapshot: PortableData.Snapshot, keys: Set<String>?) throws {
            \(raw: restore.joined(separator: "\n"))
            }
            """,
            """
            public func _$encode(into snapshot: inout PortableData.Snapshot) throws {
            \(raw: encode.joined(separator: "\n"))
            }
            """,
            """
            public static func _$describe(_ entity: PortableData.EntityDescription) {
            \(raw: describe.joined(separator: "\n"))
            }
            """,
        ]
    }

    /// Tracks every stored `var` the model persists.
    public static func expansion(
        of _: AttributeSyntax,
        attachedTo _: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext,
    ) throws -> [AttributeSyntax] {
        guard let variable = member.as(VariableDeclSyntax.self), variable.bindings.count == 1,
              let property = storedProperties(of: variable).first, property.isTracked
        else { return [] }
        return ["@PortableData._PersistedProperty"]
    }

    public static func expansion(
        of _: AttributeSyntax,
        attachedTo _: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext,
    ) throws -> [ExtensionDeclSyntax] {
        try [ExtensionDeclSyntax(
            "extension \(type.trimmed): nonisolated PortableData.PersistentModel, nonisolated Observation.Observable {}",
        )]
    }

    struct StoredProperty {
        let name: String
        /// The `inverse:` key path of a to-many `@Relationship`, which makes it derived.
        let derivedFrom: String?
        /// The initializer expression, read as the value of a row that predates the property.
        let initializer: String?
        /// `@Attribute(originalName:)` or `@Relationship(originalName:)`, as written.
        let originalName: String?
        let isUnique: Bool
        let deleteRule: String
        let isMutable: Bool
        /// A `var` gets tracked accessors, except one declared with others in one statement or
        /// with `willSet`/`didSet`, which keeps its observers and goes untracked.
        let isTracked: Bool

        var decodeArguments: String {
            var arguments = ["\"\(name)\""]
            if let originalName {
                arguments.append("original: \(originalName)")
            }
            if let initializer {
                arguments.append("default: \(initializer)")
            }
            return arguments.joined(separator: ", ")
        }
    }

    static func storedProperties(of declaration: some DeclGroupSyntax) -> [StoredProperty] {
        declaration.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }.flatMap(storedProperties)
    }

    /// Instance properties that hold state: no accessors other than observers, not
    /// `@Transient` or `@ObservationIgnored`, and not a `let` that already has its value.
    static func storedProperties(of variable: VariableDeclSyntax) -> [StoredProperty] {
        let attributes = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }
        guard !variable.modifiers.contains(where: { ["static", "class", "lazy"].contains($0.name.text) }),
              !attributes.contains(where: { ["Transient", "ObservationIgnored"].contains($0.attributeName.trimmedDescription) })
        else { return [] }
        let arguments = attributes
            .filter { ["Attribute", "Relationship"].contains($0.attributeName.trimmedDescription) }
            .flatMap { $0.arguments?.as(LabeledExprListSyntax.self).map(Array.init) ?? [] }
        func argument(_ label: String) -> String? {
            arguments.first { $0.label?.text == label }?.expression.trimmedDescription
        }
        let isUnique = arguments.contains { $0.label == nil && $0.expression.trimmedDescription == ".unique" }
        let isLet = variable.bindingSpecifier.tokenKind == .keyword(.let)
        return variable.bindings.compactMap { binding in
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
            if isLet, binding.initializer != nil { return nil }
            var hasObservers = false
            if let accessors = binding.accessorBlock?.accessors {
                guard case let .accessors(list) = accessors,
                      list.allSatisfy({ ["willSet", "didSet"].contains($0.accessorSpecifier.text) })
                else { return nil }
                hasObservers = !list.isEmpty
            }
            let isToMany = binding.typeAnnotation?.type.trimmedDescription.hasPrefix("[") ?? false
            return StoredProperty(
                name: name,
                derivedFrom: isToMany ? argument("inverse") : nil,
                initializer: binding.initializer?.value.trimmedDescription,
                originalName: argument("originalName"),
                isUnique: isUnique,
                deleteRule: argument("deleteRule") ?? ".nullify",
                isMutable: !isLet,
                isTracked: !isLet && !hasObservers && variable.bindings.count == 1,
            )
        }
    }

    /// `#Unique<T>([\.a, \.b], [\.c])`: each array is one constraint over those properties.
    static func uniqueConstraints(of declaration: some DeclGroupSyntax) -> [[String]] {
        declaration.memberBlock.members
            .compactMap { $0.decl.as(MacroExpansionDeclSyntax.self) }
            .filter { $0.macroName.text == "Unique" }
            .flatMap { expansion in
                expansion.arguments.compactMap { argument in
                    argument.expression.as(ArrayExprSyntax.self)?.elements.compactMap { element in
                        element.expression.as(KeyPathExprSyntax.self)?.components.last?.component
                            .as(KeyPathPropertyComponentSyntax.self)?.declName.baseName.text
                    }
                }
            }
    }
}

/// A `@Model` class's stored property as `@Observable` would track it, plus the model's
/// persistence bookkeeping: its value lives in `_name`, every read is reported to the
/// registrar, and every write is reported to the registrar and to the model's context.
public struct PersistedPropertyMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext,
    ) throws -> [AccessorDeclSyntax] {
        guard let name = propertyName(declaration) else { return [] }
        return [
            """
            @storageRestrictions(initializes: _\(raw: name))
            init(initialValue) {
                _\(raw: name) = initialValue
            }
            """,
            """
            get {
                _$observationRegistrar.access(self, keyPath: \\.\(raw: name))
                return _\(raw: name)
            }
            """,
            """
            set {
                PortableData._willSet(self, from: _\(raw: name), to: newValue)
                guard PortableData._differs(_\(raw: name), newValue) else {
                    _\(raw: name) = newValue
                    return
                }
                _$observationRegistrar.withMutation(of: self, keyPath: \\.\(raw: name)) {
                    _\(raw: name) = newValue
                }
            }
            """,
            """
            _modify {
                _$observationRegistrar.access(self, keyPath: \\.\(raw: name))
                _$observationRegistrar.willSet(self, keyPath: \\.\(raw: name))
                PortableData._willMutate(self)
                defer { _$observationRegistrar.didSet(self, keyPath: \\.\(raw: name)) }
                yield &_\(raw: name)
            }
            """,
        ]
    }

    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
              let name = propertyName(declaration)
        else { return [] }
        let type = binding.typeAnnotation.map { ": \($0.type.trimmedDescription)" } ?? ""
        let initializer = binding.initializer.map { " = \($0.value.trimmedDescription)" } ?? ""
        return ["private var _\(raw: name)\(raw: type)\(raw: initializer)"]
    }

    private static func propertyName(_ declaration: some DeclSyntaxProtocol) -> String? {
        declaration.as(VariableDeclSyntax.self)?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
    }
}

/// `@Attribute`, `@Relationship`, `@Transient`: markers `@Model` reads from syntax.
public struct MarkerMacro: PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf _: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        []
    }
}

/// `#Index`, `#Unique`: `@Model` reads `#Unique` from the class body; the expansion itself
/// declares nothing.
public struct DeclarationMarkerMacro: DeclarationMacro {
    public static func expansion(
        of _: some FreestandingMacroExpansionSyntax,
        in _: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        []
    }
}

@main
struct PortableDataMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ModelMacro.self, PersistedPropertyMacro.self, MarkerMacro.self, DeclarationMarkerMacro.self,
    ]
}
