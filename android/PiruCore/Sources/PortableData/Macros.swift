@attached(member, conformances: PersistentModel, names: named(_$backing), named(init), named(_$encode), named(_$resolve))
@attached(extension, conformances: PersistentModel)
public macro Model() = #externalMacro(module: "PortableDataMacros", type: "ModelMacro")

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
