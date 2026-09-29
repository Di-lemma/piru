import Observation

@attached(
    member,
    conformances: PersistentModel, Observable,
    names: named(_$backing), named(_$observationRegistrar), named(init), named(_$restore), named(_$encode), named(_$describe)
)
@attached(memberAttribute)
@attached(extension, conformances: PersistentModel, Observable)
public macro Model() = #externalMacro(module: "PortableDataMacros", type: "ModelMacro")

/// Applied by `@Model` to each stored `var`: tracked accessors over a `_name` peer.
@attached(accessor, names: named(init), named(get), named(set), named(_modify))
@attached(peer, names: prefixed(_))
public macro _PersistedProperty() = #externalMacro(module: "PortableDataMacros", type: "PersistedPropertyMacro")

@attached(peer)
public macro Attribute(
    _ options: Schema.Attribute.Option...,
    originalName: String? = nil,
    hashModifier: String? = nil,
) = #externalMacro(module: "PortableDataMacros", type: "MarkerMacro")

@attached(peer)
public macro Relationship(
    _ options: Schema.Relationship.Option...,
    deleteRule: Schema.Relationship.DeleteRule = .nullify,
    minimumModelCount: Int? = 0,
    maximumModelCount: Int? = 0,
    originalName: String? = nil,
    inverse: AnyKeyPath? = nil,
    hashModifier: String? = nil,
) = #externalMacro(module: "PortableDataMacros", type: "MarkerMacro")

@attached(peer)
public macro Transient() = #externalMacro(module: "PortableDataMacros", type: "MarkerMacro")

@freestanding(declaration)
public macro Index<T>(_ indices: [PartialKeyPath<T>]...) =
    #externalMacro(module: "PortableDataMacros", type: "DeclarationMarkerMacro")

@freestanding(declaration)
public macro Unique<T>(_ constraints: [PartialKeyPath<T>]...) =
    #externalMacro(module: "PortableDataMacros", type: "DeclarationMarkerMacro")
