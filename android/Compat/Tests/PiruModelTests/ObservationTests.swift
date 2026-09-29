import Foundation
import PortableData
import Synchronization
import Testing

/// `@Model` makes a class Observable, as SwiftData's does: a view holding a model re-renders
/// when a property it read changes, however the change is made.
@Suite("Observation", .serialized)
struct ObservationTests {
    /// Runs `read` under observation tracking and reports whether `change` then fired it.
    private func fires(_ read: () -> Void, when change: () -> Void) -> Bool {
        let fired = Recorder()
        withObservationTracking(read) {
            fired.record("fired", \DoseEntry.amount)
        }
        change()
        return !fired.entries.isEmpty
    }

    @Test
    func `Setting a stored property notifies an observer that read it`() {
        let dose = DoseEntry(substance: "caffeine", amount: 80, timestamp: origin)
        #expect(fires {
            _ = dose.amount
        } when: {
            dose.amount = 90
        })
        #expect(!fires {
            _ = dose.amount
        } when: {
            dose.notes = "unrelated"
        })
    }

    @Test
    func `Assigning an equal value does not notify`() {
        let dose = DoseEntry(substance: "caffeine", amount: 80, timestamp: origin)
        #expect(!fires {
            _ = dose.amount
        } when: {
            dose.amount = 80
        })
    }

    /// MedDetailView's "Add a Time": `reminderTimesMinutes` is computed over the stored
    /// `reminderTimesMinutesData`.
    @Test
    func `Changing a computed property over a stored one notifies an observer of it`() {
        let item = DailyDoseItem(substance: "methylphenidate", amount: 10)
        #expect(fires {
            _ = item.reminderTimesMinutes
        } when: {
            item.reminderTimesMinutes.append(480)
        })
        #expect(item.reminderTimesMinutes == [480])
    }

    @Test
    func `An in-place mutation notifies and is saved`() throws {
        let store = TestStore()
        let seeded = try seedJournal(store)
        let context = try ModelContext(store.container())
        let dose = try #require(try context.dose(seeded.doses[0]))
        #expect(fires {
            _ = dose.isApproximate
        } when: {
            dose.isApproximate.toggle()
        })
        #expect(context.hasChanges)
        try context.save()
        #expect(try ModelContext(store.container()).dose(seeded.doses[0])?.isApproximate == true)
    }

    @Test
    func `Assigning a relationship notifies observers of both sides`() throws {
        let store = TestStore()
        try seedJournal(store)
        let context = try ModelContext(store.container())
        let session = try #require(try context.sessions().first)
        let dose = DoseEntry(substance: "late", amount: 1, timestamp: origin)
        context.insert(dose)
        #expect(fires {
            _ = session.doses
        } when: {
            dose.session = session
        })
    }

    @Test
    func `Another context's save notifies observers of the models it changed`() throws {
        let store = TestStore()
        let seeded = try seedJournal(store)
        let container = try store.container()
        let viewing = ModelContext(container)
        let dose = try #require(try viewing.dose(seeded.doses[0]))
        let editing = ModelContext(container)
        try #require(try editing.dose(seeded.doses[0])).amount = 1
        try editing.save()
        #expect(fires {
            _ = dose.amount
        } when: {
            _ = try? viewing.doses()
        })
        #expect(dose.amount == 1)
    }

    /// The Android app installs Skip's registrar as the bridge; every read and write
    /// reaches it too.
    @Test
    func `An installed bridge sees each model's reads and writes`() {
        let log = Recorder()
        ModelObservation.makeBridge = { RecordingBridge(log: log) }
        defer { ModelObservation.makeBridge = nil }
        let dose = DoseEntry(substance: "caffeine", amount: 80, timestamp: origin)
        _ = dose.amount
        dose.amount = 90
        dose.isApproximate.toggle()
        #expect(log.contains("access", \DoseEntry.amount))
        #expect(log.contains("willSet", \DoseEntry.amount))
        #expect(log.contains("didSet", \DoseEntry.amount))
        #expect(log.contains("willSet", \DoseEntry.isApproximate))
        #expect(!log.contains("willSet", \DoseEntry.notes))
    }
}

private final nonisolated class Recorder: Sendable {
    private let log = Mutex<[String]>([])

    var entries: [String] {
        log.withLock { $0 }
    }

    func record(_ event: String, _ keyPath: AnyKeyPath) {
        let entry = "\(event) \(keyPath)"
        log.withLock { $0.append(entry) }
    }

    func contains(_ event: String, _ keyPath: AnyKeyPath) -> Bool {
        entries.contains("\(event) \(keyPath)")
    }
}

private nonisolated struct RecordingBridge: ModelObservationBridge {
    let log: Recorder

    func access<Subject: Observable>(_: Subject, keyPath: KeyPath<Subject, some Any>) {
        log.record("access", keyPath)
    }

    func willSet<Subject: Observable>(_: Subject, keyPath: KeyPath<Subject, some Any>) {
        log.record("willSet", keyPath)
    }

    func didSet<Subject: Observable>(_: Subject, keyPath: KeyPath<Subject, some Any>) {
        log.record("didSet", keyPath)
    }
}
