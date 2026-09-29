// A model file writes `@Model` under `import SwiftData` alone, as with SwiftData, and the
// macro's expansion names Observation's types.
@_exported import Observation

/// The registrar a `@Model` class's tracked properties report to: Observation's own, so
/// `withObservationTracking` and SwiftUI see a model change, plus a bridge a UI layer may
/// install for a renderer Observation does not reach.
public struct ModelObservationRegistrar: Sendable {
    private let native = ObservationRegistrar()
    private let slot = BridgeSlot()

    public init() {}

    public func access<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>) {
        slot.bridge?.access(subject, keyPath: keyPath)
        native.access(subject, keyPath: keyPath)
    }

    public func willSet<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>) {
        slot.bridge?.willSet(subject, keyPath: keyPath)
        native.willSet(subject, keyPath: keyPath)
    }

    public func didSet<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>) {
        slot.bridge?.didSet(subject, keyPath: keyPath)
        native.didSet(subject, keyPath: keyPath)
    }

    public func withMutation<Subject: Observable, T>(
        of subject: Subject, keyPath: KeyPath<Subject, some Any>, _ mutation: () throws -> T,
    ) rethrows -> T {
        willSet(subject, keyPath: keyPath)
        defer { didSet(subject, keyPath: keyPath) }
        return try mutation()
    }
}

/// A second registrar each model's reads and writes also go to. On Android the app installs
/// Skip's, whose registrar is what recomposes the Compose views that read a model.
public protocol ModelObservationBridge: Sendable {
    func access<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>)
    func willSet<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>)
    func didSet<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>)
}

public enum ModelObservation {
    /// Makes one bridge per model, the first time the model is read or written after this is
    /// set, so models loaded before the UI layer starts are bridged too.
    public nonisolated(unsafe) static var makeBridge: (@Sendable () -> any ModelObservationBridge)?
}

/// One model's bridge, made on first use. A model is used from one actor at a time, as its
/// context is, so the slot needs no lock.
private final class BridgeSlot: @unchecked Sendable {
    private var made: (any ModelObservationBridge)?

    var bridge: (any ModelObservationBridge)? {
        if let made { return made }
        guard let make = ModelObservation.makeBridge else { return nil }
        let bridge = make()
        made = bridge
        return bridge
    }
}
