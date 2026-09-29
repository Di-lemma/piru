// What `os` gives the iOS build beyond the Logger SkipFuse provides: the `privacy:`
// interpolation, OSAllocatedUnfairLock, and signposts (recorded nowhere on Android).

import Foundation
import SkipFuse
import Synchronization

nonisolated enum OSLogPrivacy {
    case `public`
    case `private`
    case sensitive
    case auto
}

nonisolated extension DefaultStringInterpolation {
    /// Logger messages are plain strings under SkipFuse, so the privacy class has nowhere to
    /// go: Android's log has no redaction.
    mutating func appendInterpolation(_ value: some Any, privacy _: OSLogPrivacy) {
        appendInterpolation(String(describing: value))
    }
}

final nonisolated class OSAllocatedUnfairLock<State: ~Copyable>: @unchecked Sendable {
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
    init(logger _: Logger) {}

    func makeSignpostID() -> OSSignpostID { OSSignpostID() }
    func beginInterval(_: StaticString, id _: OSSignpostID = .exclusive) -> OSSignpostIntervalState { OSSignpostIntervalState() }
    func beginInterval(_: StaticString, id _: OSSignpostID = .exclusive, _: String) -> OSSignpostIntervalState {
        OSSignpostIntervalState()
    }
    func endInterval(_: StaticString, _: OSSignpostIntervalState) {}
    func endInterval(_: StaticString, _: OSSignpostIntervalState, _: String) {}
    func emitEvent(_: StaticString, id _: OSSignpostID = .exclusive) {}
}

// MARK: - Unified log

/// Android's log cannot be read back by the app, so the store holds no entries.
final nonisolated class OSLogStore: @unchecked Sendable {
    enum Scope { case currentProcessIdentifier, system }

    init(scope _: Scope) throws {}

    func position(date _: Date) -> Position { Position() }
    func position(timeIntervalSinceLatestBoot _: TimeInterval) -> Position { Position() }

    func getEntries(at _: Position? = nil, matching _: OSLogPredicate? = nil) throws -> [OSLogEntry] { [] }

    struct Position {}
}

/// What StoreDiagnostics filters the log by; the store it goes to holds nothing to filter.
nonisolated struct OSLogPredicate {
    init(format _: String, _: Any...) {}
}

nonisolated class OSLogEntry {
    var date: Date { .distantPast }
    var composedMessage: String { "" }
}

final nonisolated class OSLogEntryLog: OSLogEntry {
    var category: String { "" }
    var subsystem: String { "" }
    var level: Level { .info }

    enum Level: Int { case undefined, debug, info, notice, error, fault }
}
