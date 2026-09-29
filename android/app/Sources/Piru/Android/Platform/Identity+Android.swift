// The legacy-identity handoff's read side: an Android install never had the old identity,
// so nothing was ever handed off.

import Foundation

nonisolated enum LegacyHandoff {
    static let successorImportedAt: Date? = nil
    static let importedJournalEntries = 0
}
