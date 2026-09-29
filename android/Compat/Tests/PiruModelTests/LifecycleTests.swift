import Foundation
import PortableData
import Testing

/// Contract items 5, 7 and 8: autosave and the pause flush, rollback, unique upserts and
/// read-only stores.
@Suite("Autosave, rollback, uniqueness")
struct LifecycleTests {
    let store = TestStore()

    /// Lets the main queue run what was scheduled on it.
    private func nextTurn() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    // MARK: 5. Autosave

    @Test
    func `The main context saves an insert on the next main-actor turn`() async throws {
        let container = try store.container()
        container.mainContext.insert(DoseEntry(substance: "caffeine", amount: 80, timestamp: origin))
        #expect(try store.count("DoseEntry") == 0)
        try await nextTurn()
        #expect(try store.count("DoseEntry") == 1)
    }

    /// SessionService's merge and title edits change held models and never save.
    @Test
    func `The main context saves an assignment to a held model and a delete`() async throws {
        let seeded = try seedJournal(store)
        let container = try store.container()
        let main = container.mainContext
        let session = try #require(try main.sessions().first)
        session.title = "Renamed"
        try main.delete(#require(try main.dose(seeded.doses[2])))
        try await nextTurn()

        let reread = try ModelContext(store.container())
        #expect(try reread.sessions().first?.title == "Renamed")
        #expect(try reread.doses().count == 2)
    }

    @Test
    func `A context you create does not autosave`() async throws {
        let context = try ModelContext(store.container())
        context.insert(DoseEntry(substance: "caffeine", amount: 80, timestamp: origin))
        try await nextTurn()
        #expect(try store.count("DoseEntry") == 0)
    }

    /// What the Android host calls from onPause: saves now, including an in-place mutation
    /// no setter reported.
    @Test
    func `flush saves the main context's pending changes at once`() throws {
        let seeded = try seedJournal(store)
        let container = try store.container()
        let dose = try #require(try container.mainContext.dose(seeded.doses[0]))
        dose.isApproximate.toggle()
        container.mainContext.insert(FavoriteSubstance(substance: "caffeine"))
        try container.flush()

        #expect(try store.count("FavoriteSubstance") == 1)
        #expect(try ModelContext(store.container()).dose(seeded.doses[0])?.isApproximate == true)
    }

    @Test
    func `The main context shows a background context's save on the next turn`() async throws {
        try seedJournal(store)
        let container = try store.container()
        let main = container.mainContext
        var notified = 0
        main.changeHandler = { notified += 1 }
        let held = try main.doses()

        let background = ModelContext(container)
        try background.doses()[0].amount = 7
        try background.save()
        try await nextTurn()

        #expect(held[0].amount == 7)
        #expect(notified > 0)
    }

    // MARK: 7. Rollback

    /// Probe P11: PiruSchema.deleteAll rolls back on error while stores hold records.
    @Test
    func `rollback restores held models, which stay registered and save later edits`() throws {
        try seedJournal(store)
        let context = try ModelContext(store.container())
        let prefs = try #require(try context.fetch(FetchDescriptor<NotificationPreferences>()).first)
        prefs.quietHoursStartMinutes = 1
        prefs.masterEnabled = false
        context.rollback()

        #expect(prefs.quietHoursStartMinutes == 23 * 60)
        #expect(prefs.masterEnabled)
        #expect(prefs.modelContext === context)
        #expect(try context.fetch(FetchDescriptor<NotificationPreferences>()).first === prefs)

        prefs.quietHoursStartMinutes = 5
        try context.save()
        #expect(try store.rows("NotificationPreferences").values.first?["quietHoursStartMinutes"] as? Int == 5)
    }

    @Test
    func `rollback forgets inserts, restores deletes and relationships`() throws {
        try seedJournal(store)
        let context = try ModelContext(store.container())
        let session = try #require(try context.sessions().first)
        let doses = try context.doses()
        context.insert(DoseEntry(substance: "never saved", amount: 1, timestamp: origin))
        context.delete(doses[0])
        doses[1].session = nil
        context.rollback()

        #expect(try context.doses().map(\.substance) == ["caffeine0", "caffeine1", "caffeine2"])
        #expect(!doses[0].isDeleted)
        #expect(doses[1].session === session)
        #expect(session.doses?.count == 3)
        #expect(!context.hasChanges)
        try context.save()
        #expect(try store.count("DoseEntry") == 3)
    }

    /// Probe P11's last part.
    @Test
    func `Deleting then inserting the same model keeps its row`() throws {
        try seedJournal(store)
        let context = try ModelContext(store.container())
        let dose = try context.doses()[0]
        context.delete(dose)
        context.insert(dose)
        try context.save()
        #expect(try store.count("DoseEntry") == 3)
    }

    // MARK: 8. Unique attributes and read-only stores

    /// Probe P10.
    @Test
    func `Inserting a model whose unique attribute is taken updates that row`() throws {
        let context = try ModelContext(store.container())
        context.insert(FavoriteSubstance(substance: "caffeine", sortOrder: 1))
        context.insert(FavoriteSubstance(substance: "caffeine", sortOrder: 2))
        try context.save()
        #expect(try store.count("FavoriteSubstance") == 1)

        let other = try ModelContext(store.container())
        let replacement = FavoriteSubstance(substance: "caffeine", sortOrder: 3)
        other.insert(replacement)
        try other.save()
        #expect(try store.count("FavoriteSubstance") == 1)
        #expect(try store.rows("FavoriteSubstance").values.first?["sortOrder"] as? Int == 3)
        #expect(try other.fetch(FetchDescriptor<FavoriteSubstance>()).map(\.sortOrder) == [3])
        #expect(try context.fetch(FetchDescriptor<FavoriteSubstance>()).map(\.sortOrder) == [3])
    }

    @Test
    func `A tolerance cache row for a known target upserts`() throws {
        try seedJournal(store)
        let context = try ModelContext(store.container())
        context.insert(ToleranceState(target: "serotonin", sAcute: 0.5))
        try context.save()
        #expect(try store.count("ToleranceState") == 1)
        #expect(try store.rows("ToleranceState").values.first?["sAcute"] as? Double == 0.5)
    }

    @Test
    func `A read-only container reads and cannot write`() throws {
        try seedJournal(store)
        let before = try store.generations("DoseEntry")
        let container = try store.container(allowsSave: false)
        let context = ModelContext(container)
        #expect(try context.doses().count == 3)

        try context.doses()[0].amount = 1
        context.insert(FavoriteSubstance(substance: "caffeine"))
        #expect(throws: PortableDataError.self) { try context.save() }
        #expect(try store.generations("DoseEntry") == before)
        #expect(try store.count("FavoriteSubstance") == 0)
    }

    @Test
    func `Opening a store read-only does not create or change it`() throws {
        #expect(throws: (any Error).self) { _ = try store.container(allowsSave: false) }
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }
}
