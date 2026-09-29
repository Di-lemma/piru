import Foundation
import PortableData
import Testing

/// Contract item 9: loading and saving grow linearly with the journal, and a context loads
/// only the entities the one it fetched reaches.
@Suite("Scaling", .serialized)
struct ScalingTests {
    /// A journal of `doses` entries, five to a session.
    private func journal(doses: Int) throws -> TestStore {
        let store = TestStore()
        let context = try ModelContext(store.container())
        var session = Session(startDate: origin)
        for index in 0 ..< doses {
            if index % 5 == 0 {
                session = Session(startDate: origin.addingTimeInterval(Double(index) * 600))
                context.insert(session)
            }
            let dose = DoseEntry(substance: "s\(index % 40)", amount: Double(index), timestamp: origin.addingTimeInterval(Double(index) * 600))
            dose.session = session
            context.insert(dose)
        }
        try context.save()
        return store
    }

    private struct Timing {
        let load: Duration
        let save: Duration
    }

    private func time(_ store: TestStore) throws -> Timing {
        let clock = ContinuousClock()
        let context = try ModelContext(store.container())
        var loaded = 0
        let load = try clock.measure { loaded = try context.doses().count }
        #expect(loaded > 0)
        try context.doses()[0].notes = "edited"
        let save = try clock.measure { try context.save() }
        return Timing(load: load, save: save)
    }

    /// Probes P14/P15: the inverse pass was a scan per session, quadratic in the journal.
    /// Four times the journal costs about four times as long; quadratic growth would cost
    /// sixteen. The bound leaves room for a busy machine.
    @Test
    func `Loading and saving four times the journal costs about four times as much`() throws {
        let small = try time(journal(doses: 1500))
        let large = try time(journal(doses: 6000))
        #expect(large.load < small.load * 8, "load: \(small.load) → \(large.load)")
        #expect(large.save < small.save * 8, "save: \(small.save) → \(large.save)")
    }

    /// ToleranceStore's background context fetches only its cache.
    @Test
    func `A context that fetches an unrelated entity does not load the journal`() throws {
        let store = try journal(doses: 50)
        let seeded = try ModelContext(store.container()).doses()[0].persistentModelID
        let context = try ModelContext(store.container())
        _ = try context.fetch(FetchDescriptor<ToleranceState>())
        let held: DoseEntry? = context.registeredModel(for: seeded)
        #expect(held == nil)
        _ = try context.sessions()
        let loaded: DoseEntry? = context.registeredModel(for: seeded)
        #expect(loaded != nil)
    }
}
