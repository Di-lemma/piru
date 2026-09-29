import Foundation
import Synchronization

#if canImport(Android)
    import Android
#endif

// MARK: - Logger

public enum OSLogType: Sendable {
    case debug
    case info
    case `default`
    case error
    case fault
}

public struct OSLogPrivacy: Sendable {
    public static let `public` = OSLogPrivacy()
    public static let `private` = OSLogPrivacy()
    public static let sensitive = OSLogPrivacy()
    public static let auto = OSLogPrivacy()
}

public struct OSLogMessage: ExpressibleByStringInterpolation, Sendable {
    public struct StringInterpolation: StringInterpolationProtocol {
        var text = ""

        public init(literalCapacity: Int, interpolationCount _: Int) {
            text.reserveCapacity(literalCapacity)
        }

        public mutating func appendLiteral(_ literal: String) {
            text += literal
        }

        public mutating func appendInterpolation(_ value: some Any, privacy _: OSLogPrivacy = .auto) {
            text += String(describing: value)
        }
    }

    let text: String

    public init(stringLiteral value: String) {
        text = value
    }

    public init(stringInterpolation: StringInterpolation) {
        text = stringInterpolation.text
    }
}

public struct Logger: Sendable {
    let subsystem: String
    let category: String

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    public init() {
        self.init(subsystem: "", category: "")
    }

    public func log(level: OSLogType, _ message: OSLogMessage) {
        write(level, message.text)
    }

    public func log(_ message: OSLogMessage) { write(.default, message.text) }
    public func trace(_ message: OSLogMessage) { write(.debug, message.text) }
    public func debug(_ message: OSLogMessage) { write(.debug, message.text) }
    public func info(_ message: OSLogMessage) { write(.info, message.text) }
    public func notice(_ message: OSLogMessage) { write(.default, message.text) }
    public func warning(_ message: OSLogMessage) { write(.error, message.text) }
    public func error(_ message: OSLogMessage) { write(.error, message.text) }
    public func critical(_ message: OSLogMessage) { write(.fault, message.text) }
    public func fault(_ message: OSLogMessage) { write(.fault, message.text) }

    private func write(_ level: OSLogType, _ text: String) {
        #if canImport(Android)
            let priority: android_LogPriority = switch level {
            case .debug: ANDROID_LOG_DEBUG
            case .info: ANDROID_LOG_INFO
            case .default: ANDROID_LOG_INFO
            case .error: ANDROID_LOG_ERROR
            case .fault: ANDROID_LOG_FATAL
            }
            _ = __android_log_write(Int32(priority.rawValue), "\(subsystem)/\(category)", text)
        #else
            FileHandle.standardError.write(Data("[\(category)] \(text)\n".utf8))
        #endif
    }
}

// MARK: - OSAllocatedUnfairLock

public final class OSAllocatedUnfairLock<State: ~Copyable>: @unchecked Sendable {
    private let mutex: Mutex<State>

    public init(initialState: consuming sending State) {
        mutex = Mutex(initialState)
    }

    public func withLock<R: ~Copyable, E: Error>(
        _ body: (inout sending State) throws(E) -> sending R,
    ) throws(E) -> sending R {
        try mutex.withLock(body)
    }
}

public extension OSAllocatedUnfairLock where State == () {
    convenience init() {
        self.init(initialState: ())
    }

    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        try mutex.withLock { _ in try body() }
    }
}

// MARK: - OSSignposter

public struct OSSignpostID: Sendable {
    public static let exclusive = OSSignpostID()
}

public struct OSSignpostIntervalState: Sendable {}

public struct OSSignposter: Sendable {
    public init(logger _: Logger) {}
    public init() {}

    public func makeSignpostID() -> OSSignpostID { OSSignpostID() }

    public func beginInterval(_: StaticString, id _: OSSignpostID = .exclusive) -> OSSignpostIntervalState {
        OSSignpostIntervalState()
    }

    public func beginInterval(
        _: StaticString, id _: OSSignpostID = .exclusive, _: OSLogMessage,
    ) -> OSSignpostIntervalState {
        OSSignpostIntervalState()
    }

    public func endInterval(_: StaticString, _: OSSignpostIntervalState) {}

    public func endInterval(_: StaticString, _: OSSignpostIntervalState, _: OSLogMessage) {}

    public func emitEvent(_: StaticString, id _: OSSignpostID = .exclusive) {}
}
