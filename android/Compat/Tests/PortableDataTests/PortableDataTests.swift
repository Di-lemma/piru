import Foundation
import PortableData
import Testing

enum Route: String, Codable {
    case oral
    case insufflation
}

@Model
final class Dose {
    #Index<Dose>([\.timestamp])

    var id: UUID = UUID()
    var substance: String
    var amount: Double
    var route: Route
    var timestamp: Date
    var notes: String?
    var session: Visit?

    var label: String {
        "\(amount) \(substance)"
    }

    init(substance: String, amount: Double, route: Route = .oral, timestamp: Date, notes: String? = nil) {
        self.substance = substance
        self.amount = amount
        self.route = route
        self.timestamp = timestamp
        self.notes = notes
    }
}

@Model
final class Visit {
    @Attribute(.unique) var id: UUID
    var title: String?
    @Relationship(deleteRule: .nullify, inverse: \Dose.session)
    var doses: [Dose]?

    init(title: String?) {
        id = UUID()
        self.title = title
    }
}

@Suite("PortableData")
struct PortableDataTests {
    let url = FileManager.default.temporaryDirectory.appending(path: "portable-\(UUID().uuidString).sqlite")

    @Test
    func `A saved graph reloads from disk with values, predicates, sorting and both relationship sides`() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        do {
            let container = try ModelContainer(for: Dose.self, Visit.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            let visit = Visit(title: "Saturday")
            for (index, name) in ["caffeine", "mdma", "caffeine"].enumerated() {
                let dose = Dose(substance: name, amount: Double(100 + index), timestamp: start.addingTimeInterval(Double(index) * 3600))
                dose.session = visit
                context.insert(dose)
            }
            context.insert(Dose(substance: "melatonin", amount: 3, route: .oral, timestamp: start, notes: "sleep"))
            try context.save()
        }

        let container = try ModelContainer(for: Dose.self, Visit.self, configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        let cutoff = start.addingTimeInterval(1800)
        let recent = try context.fetch(FetchDescriptor<Dose>(
            predicate: #Predicate { $0.timestamp > cutoff },
            sortBy: [SortDescriptor(\.amount, order: .reverse)],
        ))
        #expect(recent.map(\.amount) == [102, 101])
        #expect(recent.map(\.substance) == ["caffeine", "mdma"])

        let visits = try context.fetch(FetchDescriptor<Visit>())
        #expect(visits.count == 1)
        #expect(visits.first?.title == "Saturday")
        #expect(visits.first?.doses?.count == 3)
        #expect(recent.allSatisfy { $0.session === visits.first })

        let melatonin = try context.fetch(FetchDescriptor<Dose>(predicate: #Predicate { $0.substance == "melatonin" }))
        #expect(melatonin.first?.notes == "sleep")
        #expect(melatonin.first?.session == nil)
        #expect(try context.fetchCount(FetchDescriptor<Dose>()) == 4)
    }

    @Test
    func `Deleting the one side leaves the many side pointing at nothing after a reload`() throws {
        do {
            let container = try ModelContainer(for: Dose.self, Visit.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            let visit = Visit(title: "gone")
            let dose = Dose(substance: "caffeine", amount: 50, timestamp: .now)
            dose.session = visit
            context.insert(dose)
            try context.save()
            context.delete(visit)
            try context.save()
        }
        let context = try ModelContext(ModelContainer(for: Dose.self, Visit.self, configurations: ModelConfiguration(url: url)))
        #expect(try context.fetch(FetchDescriptor<Visit>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Dose>()).first?.session == nil)
    }
}
