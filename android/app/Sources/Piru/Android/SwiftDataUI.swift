// SwiftData's SwiftUI surface over PortableData: `.modelContainer(_:)`, the `modelContext`
// environment value, and `@Query`. It lives in the app module because it needs SwiftUI,
// which on Android is SkipFuseUI.

import SwiftData
import SwiftUI

extension EnvironmentValues {
    @Entry var modelContext: ModelContext = MainActor.assumeIsolated { ModelContainer.application!.mainContext }
}

/// Relays the main context's changes into Skip's Observation, which is what recomposes views.
@Observable
final class ModelChanges {
    static let shared = ModelChanges()
    var token = 0
}

/// A model's reads and writes, reported to Skip's registrar as well: in this file
/// `Observation.ObservationRegistrar` is Skip's, which recomposes the Compose views that read
/// a property, where PortableData's registrar reaches only Observation.
private struct SkipModelObservation: ModelObservationBridge {
    let registrar = Observation.ObservationRegistrar()

    func access<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>) {
        registrar.access(subject, keyPath: keyPath)
    }

    func willSet<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>) {
        registrar.willSet(subject, keyPath: keyPath)
    }

    func didSet<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>) {
        registrar.didSet(subject, keyPath: keyPath)
    }
}

extension View {
    func modelContainer(_ container: ModelContainer) -> some View {
        ModelObservation.makeBridge = { SkipModelObservation() }
        ModelContainer.application = container
        container.mainContext.changeHandler = { ModelChanges.shared.token += 1 }
        return environment(\.modelContext, container.mainContext)
    }

    func modelContext(_ context: ModelContext) -> some View {
        environment(\.modelContext, context)
    }
}

/// Fetches on every read from the main context's identity map, which is an in-memory filter
/// once the entity is loaded. Reading ``ModelChanges`` subscribes the reading view to inserts,
/// deletes and saves.
@propertyWrapper
struct Query<Element: PersistentModel> {
    private let descriptor: FetchDescriptor<Element>

    var wrappedValue: [Element] {
        guard let context = ModelContainer.application?.mainContext else { return [] }
        _ = ModelChanges.shared.token
        return (try? context.fetch(descriptor)) ?? []
    }

    init() {
        descriptor = FetchDescriptor()
    }

    init(_ descriptor: FetchDescriptor<Element>, animation _: Animation? = nil) {
        self.descriptor = descriptor
    }

    init(_ descriptor: FetchDescriptor<Element>, transaction _: Transaction?) {
        self.descriptor = descriptor
    }

    init(filter: Predicate<Element>? = nil, sort: [SortDescriptor<Element>] = [], animation _: Animation? = nil) {
        descriptor = FetchDescriptor(predicate: filter, sortBy: sort)
    }

    init(
        filter: Predicate<Element>? = nil,
        sort keyPath: KeyPath<Element, some Comparable> & Sendable,
        order: SortOrder = .forward,
        animation _: Animation? = nil,
    ) {
        descriptor = FetchDescriptor(predicate: filter, sortBy: [SortDescriptor(keyPath, order: order)])
    }

    init(
        filter: Predicate<Element>? = nil,
        sort keyPath: KeyPath<Element, (some Comparable)?> & Sendable,
        order: SortOrder = .forward,
        animation _: Animation? = nil,
    ) {
        descriptor = FetchDescriptor(predicate: filter, sortBy: [SortDescriptor(keyPath, order: order)])
    }
}
