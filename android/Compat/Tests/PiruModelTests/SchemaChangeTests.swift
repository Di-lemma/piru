import Foundation
import GRDB
import PortableData
import Testing

/// A model whose `note` was stored as `oldNote` by an earlier build. No app model renames a
/// property yet, so the rename is exercised here.
@Model
final class RenamedNote {
    @Attribute(originalName: "oldNote") var note: String?
    var title: String

    init(title: String) {
        self.title = title
    }
}

/// Contract items 1 and 2: rows written by another build of the app read, and keep what
/// this build does not know; a row that cannot be read is skipped and reported.
@Suite("Rows from other builds")
struct SchemaChangeTests {
    let store = TestStore()

    /// Probe P01: `isUnknownDose` and friends were added with defaults after rows existed.
    @Test
    func `A row stored before a defaulted property existed reads with its default`() throws {
        try seedJournal(store)
        try store.rewrite("DoseEntry", "json_remove(CAST(data AS TEXT), '$.isUnknownDose', '$.isApproximate', '$.isBackgroundMed')")
        try store.rewrite("Session", "json_remove(CAST(data AS TEXT), '$.checkInOffered', '$.checkInOffsetsData')")
        try store.rewrite("NotificationPreferences", "json_remove(CAST(data AS TEXT), '$.quietHoursStartMinutes')")

        let container = try store.container()
        let context = ModelContext(container)
        let doses = try context.doses()
        #expect(doses.count == 3)
        #expect(doses.allSatisfy { !$0.isUnknownDose && !$0.isApproximate && !$0.isBackgroundMed })
        let session = try #require(try context.sessions().first)
        #expect(!session.checkInOffered)
        #expect(session.doses?.count == 3)
        #expect(try context.fetch(FetchDescriptor<NotificationPreferences>()).first?.quietHoursStartMinutes == 23 * 60)
        #expect(container.loadFailures.isEmpty)

        // The app's seed-if-missing singletons find the stored row rather than adding a second.
        #expect(try context.fetchCount(FetchDescriptor<NotificationPreferences>()) == 1)
    }

    @Test
    func `A row stored before an optional property existed reads it as nil`() throws {
        try seedJournal(store)
        try store.rewrite("DoseEntry", "json_remove(CAST(data AS TEXT), '$.mealRaw', '$.hadGrapefruit', '$.drinkName')")
        let doses = try ModelContext(store.container()).doses()
        #expect(doses.count == 3)
        #expect(doses.allSatisfy { $0.meal == nil && $0.hadGrapefruit == nil && $0.drinkName == nil })
    }

    /// Probe P04: an older build saving must not erase what a newer build stored.
    @Test
    func `Keys this build does not know survive its save`() throws {
        let seeded = try seedJournal(store)
        try store.rewrite("DoseEntry", "json_set(CAST(data AS TEXT), '$.futureField', 'kept')")
        let context = try ModelContext(store.container())
        let dose = try #require(try context.dose(seeded.doses[0]))
        dose.notes = "edited by an older build"
        try context.save()

        let rows = try store.rows("DoseEntry")
        #expect(rows.count == 3)
        #expect(rows.values.allSatisfy { $0["futureField"] as? String == "kept" })
        #expect(rows[dose.persistentModelID.primaryKey]?["notes"] as? String == "edited by an older build")
    }

    /// Probe P02.
    @Test
    func `originalName reads the old key, and a save moves the value to the new one`() throws {
        let container = try ModelContainer(for: RenamedNote.self, configurations: ModelConfiguration(url: store.url))
        _ = container
        try store.execute(#"INSERT INTO portable_models (entity, pk, data) VALUES ('RenamedNote', 'r1', CAST('{"oldNote":"allergic to X","title":"t"}' AS BLOB))"#)

        let context = ModelContext(container)
        let renamed = try #require(try context.fetch(FetchDescriptor<RenamedNote>()).first)
        #expect(renamed.note == "allergic to X")

        renamed.title = "edited"
        try context.save()
        let row = try #require(try store.rows("RenamedNote")["r1"])
        #expect(row["note"] as? String == "allergic to X")
        #expect(row["oldNote"] == nil)
        #expect(row["title"] as? String == "edited")
    }

    /// Probe P03: a route a newer build added hides nothing else.
    @Test
    func `A row that cannot be read is skipped and reported, and the rest of the table loads`() throws {
        let seeded = try seedJournal(store)
        try store.rewrite("DoseEntry", "json_set(CAST(data AS TEXT), '$.route', 'teleport')", where: "CAST(data AS TEXT) LIKE '%caffeine1%'")
        try store.execute("INSERT INTO portable_models (entity, pk, data) VALUES ('DoseEntry', 'garbage', CAST('{not json' AS BLOB))")

        let container = try store.container()
        let context = ModelContext(container)
        #expect(try context.doses().map(\.id) == [seeded.doses[0], seeded.doses[2]])
        #expect(try context.doses().count == 2)
        #expect(Set(container.loadFailures.map(\.entity)) == ["DoseEntry"])
        #expect(container.loadFailures.count == 2)
        #expect(try context.fetch(FetchDescriptor<NotificationPreferences>()).count == 1)

        // Saving around the unreadable rows leaves them as they were.
        try context.doses()[0].notes = "saved"
        try context.save()
        #expect(try store.count("DoseEntry") == 4)
        let unreadable = try store.rows("DoseEntry").values.first { $0["substance"] as? String == "caffeine1" }
        #expect(unreadable?["route"] as? String == "teleport")
    }

    /// A store the earlier PortableData wrote, with no generation column, opens and upgrades.
    @Test
    func `A store from before generations opens and upgrades`() throws {
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = try DatabaseQueue(path: store.url.path)
        try legacy.write { db in
            try db.execute(sql: """
            CREATE TABLE portable_models (
                entity TEXT NOT NULL, pk TEXT NOT NULL, data BLOB NOT NULL, PRIMARY KEY (entity, pk)
            ) WITHOUT ROWID
            """)
            try db.execute(sql: #"""
            INSERT INTO portable_models VALUES ('FavoriteSubstance', 'f1',
                CAST('{"createdAt":812345678.5,"sortOrder":2,"substance":"caffeine"}' AS BLOB))
            """#)
        }
        try legacy.close()

        let context = try ModelContext(store.container())
        let favorite = try #require(try context.fetch(FetchDescriptor<FavoriteSubstance>()).first)
        #expect(favorite.substance == "caffeine")
        #expect(favorite.sortOrder == 2)
        favorite.sortOrder = 3
        try context.save()
        #expect(try store.rows("FavoriteSubstance")["f1"]?["sortOrder"] as? Int == 3)
    }
}
