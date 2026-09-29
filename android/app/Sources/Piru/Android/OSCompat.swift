// What `os` gives the iOS build beyond the Logger SkipFuse provides: the `privacy:`
// interpolation, OSAllocatedUnfairLock, and signposts (recorded nowhere on Android).

import Foundation
import SkipFuse
import Synchronization

nonisolated enum OSLogPrivacy {
    case `public`, `private`, sensitive, auto
}

nonisolated extension DefaultStringInterpolation {
    /// Logger messages are plain strings under SkipFuse, so the privacy class has nowhere to
    /// go: Android's log has no redaction.
    mutating func appendInterpolation(_ value: some Any, privacy: OSLogPrivacy) {
        appendInterpolation(String(describing: value))
    }
}

nonisolated final class OSAllocatedUnfairLock<State: ~Copyable>: @unchecked Sendable {
    private let mutex: Mutex<State>

    init(initialState: consuming sending State) {
        mutex = Mutex(initialState)
    }

    func withLock<R: ~Copyable, E: Error>(_ body: (inout sending State) throws(E) -> sending R) throws(E) -> sending R {
        try mutex.withLock(body)
    }
}

nonisolated struct OSSignpostID: Sendable {
    static let exclusive = OSSignpostID()
}

nonisolated struct OSSignpostIntervalState: Sendable {}

nonisolated struct OSSignposter: Sendable {
    init(logger: Logger) {}

    func makeSignpostID() -> OSSignpostID { OSSignpostID() }
    func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive) -> OSSignpostIntervalState { OSSignpostIntervalState() }
    func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: String) -> OSSignpostIntervalState {
        OSSignpostIntervalState()
    }
    func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {}
    func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState, _ message: String) {}
    func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive) {}
}

// MARK: - Unified log

/// Android's log cannot be read back by the app, so the store holds no entries.
nonisolated final class OSLogStore: @unchecked Sendable {
    enum Scope { case currentProcessIdentifier, system }

    init(scope: Scope) throws {}

    func position(date: Date) -> Position { Position() }
    func position(timeIntervalSinceLatestBoot seconds: TimeInterval) -> Position { Position() }

    func getEntries(at position: Position? = nil, matching predicate: OSLogPredicate? = nil) throws -> [OSLogEntry] { [] }

    struct Position {}
}

/// What StoreDiagnostics filters the log by; the store it goes to holds nothing to filter.
nonisolated struct OSLogPredicate {
    init(format: String, _ arguments: Any...) {}
}

nonisolated class OSLogEntry {
    var date: Date { .distantPast }
    var composedMessage: String { "" }
}

nonisolated final class OSLogEntryLog: OSLogEntry {
    var category: String { "" }
    var subsystem: String { "" }
    var level: Level { .info }

    enum Level: Int { case undefined, debug, info, notice, error, fault }
}
