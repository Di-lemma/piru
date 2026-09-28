import Foundation
import SwiftData
@testable import Piru

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("usage: piru-smoke <piru-substances.sqlite> <Localizable.xcstrings> <writable-dir>")
    exit(64)
}
let catalogURL = URL(filePath: arguments[1])
let stringsURL = URL(filePath: arguments[2])
let workDir = URL(filePath: arguments[3])

#if os(Android)
    let platform = "Android"
#elseif os(macOS)
    let platform = "macOS"
#else
    let platform = "other"
#endif
print("platform: \(platform)")

/// 1. The substance catalog through the app's own store.
let store = SubstanceStore(
    substancesDBURL: catalogURL,
    userPrefsDBURL: workDir.appending(path: "prefs.sqlite"),
    prewarmsAllCache: false,
)
guard let caffeine = store.lookup("Caffeine") else {
    print("FAIL: Caffeine did not resolve")
    exit(1)
}
print("substance: \(caffeine.name), category \(caffeine.category.rawValue)")
if let ladder = caffeine.doseRange(for: .oral) {
    print("oral ladder: threshold \(ladder.threshold.map { "\($0)" } ?? "-"), common \(ladder.common.map { "\($0)" } ?? "-")")
}
if let duration = caffeine.duration(for: .oral) {
    print("oral duration: ~\(Int(duration.estimatedTotalMinutes)) min total")
}
let reference = caffeine.referenceDose(route: .oral, unit: caffeine.unit(for: .oral))
print("reference dose: \(reference.map { "\($0) \(caffeine.unit(for: .oral))" } ?? "none")")

// 2. The PK model on the catalog's half-life.
if let halfLife = PKResolver.halfLifeMinutes(substance: caffeine) {
    let ke = Foundation.log(2.0) / halfLife
    let ka = Foundation.log(2.0) / 30
    let tmax = PKModel.tmax(ke: ke, ka: ka)
    let remaining = PKModel.fractionRemainingInBody(at: 6 * 60, ke: ke, ka: ka)
    print("half-life \(Int(halfLife)) min → tmax \(Int(tmax)) min, \(Int(remaining * 100))% in body at 6 h")
}

/// 3. The journal: a session with two doses, saved, then read back by a fresh container.
let storeURL = workDir.appending(path: "journal.store")
try? FileManager.default.removeItem(at: storeURL)
let schema = Schema([DoseEntry.self, Session.self, SessionNote.self])
do {
    let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: storeURL))
    let context = ModelContext(container)
    let session = Session(startDate: .now.addingTimeInterval(-7200), title: "Morning")
    for (name, amount) in [("Caffeine", 100.0), ("L-Theanine", 200.0)] {
        let entry = DoseEntry(substance: name, amount: amount, unit: "mg", route: .oral, timestamp: .now.addingTimeInterval(-3600))
        entry.session = session
        context.insert(entry)
    }
    try context.save()
}
let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: storeURL))
let context = ModelContext(container)
let caffeineDoses = try context.fetch(FetchDescriptor<DoseEntry>(
    predicate: #Predicate { $0.substance == "Caffeine" },
    sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
))
let sessions = try context.fetch(FetchDescriptor<Session>())
print("journal: \(caffeineDoses.count) caffeine dose, \(sessions.first?.doses?.count ?? 0) doses in \"\(sessions.first?.title ?? "?")\"")

// 4. The string catalog, read from the xcstrings file where Foundation has no localization.
#if canImport(Darwin)
    let chinese = "兴奋剂"
    print("category label: \(String(localized: caffeine.category.displayName)) (Apple localization)")
#else
    try LocalizationCatalog.shared.load(xcstrings: stringsURL, preferred: ["en"])
    let english = String(localized: caffeine.category.displayName)
    try LocalizationCatalog.shared.load(xcstrings: stringsURL, preferred: ["zh-Hans"])
    let chinese = String(localized: caffeine.category.displayName)
    print("category label: en \(english), zh-Hans \(chinese)")
#endif

let passed = caffeineDoses.count == 1 && sessions.first?.doses?.count == 2 && chinese == "兴奋剂"
print(passed ? "PASS" : "FAIL")
exit(passed ? 0 : 1)
