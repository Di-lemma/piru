import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Model`: gives a class the members ``PersistentModel`` needs — a backing that holds
/// its store identity, an initializer that rebuilds it from a stored snapshot, and the
/// two passes that write it out and reconnect its relationships.
///
/// The generated code names every stored property and lets the property's declared type
/// pick the overload: a `Codable` value is stored as itself, a model or an array of
/// models as the identifiers it points at. That is what lets the macro work from syntax
/// alone, without knowing which of the class's types are models.
public struct ModelMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        let properties = storedProperties(of: declaration)
        let decode = properties.map { "self.\($0.name) = try snapshot.decode(\"\($0.name)\")" }
        // A to-many side with an `inverse:` is rebuilt from the other side, never stored.
        let encode = properties.filter { $0.derivedFrom == nil }.map { "snapshot.encode(self.\($0.name), \"\($0.name)\")" }
        let resolve = properties.map { property in
            if let inverse = property.derivedFrom {
                return "try resolver.resolveInverse(&self.\(property.name), \(inverse), owner: self)"
            }
            return "try resolver.resolve(&self.\(property.name), \"\(property.name)\")"
        }
        return [
            "public let _$backing = PortableData.ModelBacking()",
            """
            public init(_$snapshot snapshot: PortableData.Snapshot) throws {
            \(raw: decode.joined(separator: "\n"))
            _$backing.identifier = snapshot.identifier
            }
            """,
            """
            public func _$encode(into snapshot: inout PortableData.Snapshot) {
            \(raw: encode.joined(separator: "\n"))
            }
            """,
            """
            public func _$resolve(_ resolver: PortableData.RelationshipResolver) throws {
            \(raw: resolve.joined(separator: "\n"))
            }
            """,
        ]
    }

    public static func expansion(
        of _: AttributeSyntax,
        attachedTo _: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext,
    ) throws -> [ExtensionDeclSyntax] {
        try [ExtensionDeclSyntax("extension \(type.trimmed): nonisolated PortableData.PersistentModel {}")]
    }

    struct StoredProperty {
        let name: String
        /// The `inverse:` key path of a to-many `@Relationship`, which makes it derived.
        let derivedFrom: String?
    }

    /// Instance properties that hold state: no accessors other than observers, not
    /// `@Transient` or `@ObservationIgnored`, and not a `let` that already has its value.
    static func storedProperties(of declaration: some DeclGroupSyntax) -> [StoredProperty] {
        declaration.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .filter { variable in
                !variable.modifiers.contains { ["static", "class"].contains($0.name.text) }
                    && !variable.attributes.contains { attribute in
                        let name = attribute.as(AttributeSyntax.self)?.attributeName.trimmedDescription
                        return name == "Transient" || name == "ObservationIgnored"
                    }
            }
            .flatMap { variable -> [StoredProperty] in
                let inverse = variable.attributes.lazy.compactMap { $0.as(AttributeSyntax.self) }
                    .first { $0.attributeName.trimmedDescription == "Relationship" }?
                    .arguments?.as(LabeledExprListSyntax.self)?
                    .first { $0.label?.text == "inverse" }?.expression.trimmedDescription
                return variable.bindings.compactMap { binding in
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
                    if variable.bindingSpecifier.tokenKind == .keyword(.let), binding.initializer != nil { return nil }
                    if let accessors = binding.accessorBlock?.accessors {
                        guard case let .accessors(list) = accessors,
                              list.allSatisfy({ ["willSet", "didSet"].contains($0.accessorSpecifier.text) })
                        else { return nil }
                    }
                    let isToMany = binding.typeAnnotation?.type.trimmedDescription.hasPrefix("[") ?? false
                    return StoredProperty(name: name, derivedFrom: isToMany ? inverse : nil)
                }
            }
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

/// `#Index`, `#Unique`: store-level hints that a whole-entity load has no use for.
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
    let providingMacros: [Macro.Type] = [ModelMacro.self, MarkerMacro.self, DeclarationMarkerMacro.self]
}
