import Synchronization

/// Where PortableData reports what it could not load or save. The host installs a sink that
/// writes to its platform's log; PortableData itself imports no logging module, so the stand-in
/// `os` it would otherwise need never reaches an app that builds against the real one.
public enum PortableDataLog {
    private static let sink = Mutex<(@Sendable (_ category: String, _ message: String) -> Void)?>(nil)

    /// Routes every report to `write`.
    public static func install(_ write: @escaping @Sendable (_ category: String, _ message: String) -> Void) {
        sink.withLock { $0 = write }
    }

    static func error(_ category: String, _ message: String) {
        sink.withLock { $0 }?(category, message)
    }
}
