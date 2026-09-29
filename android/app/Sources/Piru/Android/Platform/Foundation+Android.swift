// Foundation API the iOS build uses that Android's Foundation lacks, answered the way the
// shared code already handles on a device without the feature: no iCloud, no app-group
// container, no security scope.

import Dispatch
import Foundation
import SkipFuse

extension AndroidBundle {
    /// SwiftPM's generated `Bundle.module` accessor passes a private class that the module's
    /// MainActor default isolation makes main-actor-bound, and that metatype does not convert
    /// to `AnyClass` at the call. The generic parameter takes it as is.
    convenience init(for type: (some AnyObject).Type) {
        self.init(for: type as AnyClass)
    }
}

nonisolated extension FileManager {
    /// Android has no iCloud Drive.
    func url(forUbiquityContainerIdentifier _: String?) -> URL? { nil }

    var ubiquityIdentityToken: (any NSCoding & NSCopying & NSObjectProtocol)? { nil }

    func startDownloadingUbiquitousItem(at _: URL) throws {}

    /// An app group shares a container with extensions; Android's app has none, so its own
    /// files directory is the group container.
    func containerURL(forSecurityApplicationGroupIdentifier _: String) -> URL? {
        urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
}

nonisolated extension URL {
    /// Android grants a picked document for as long as the app holds the URI.
    func startAccessingSecurityScopedResource() -> Bool { true }

    func stopAccessingSecurityScopedResource() {}
}

typealias NSErrorPointer = UnsafeMutablePointer<NSError?>?

/// Coordinates nothing: only this process touches the app's files on Android.
final nonisolated class NSFileCoordinator {
    init(filePresenter _: Any? = nil) {}

    func coordinate(readingItemAt url: URL, options _: ReadingOptions = [], error _: NSErrorPointer, byAccessor reader: (URL) -> Void) {
        reader(url)
    }

    func coordinate(writingItemAt url: URL, options _: WritingOptions = [], error _: NSErrorPointer, byAccessor writer: (URL) -> Void) {
        writer(url)
    }

    struct ReadingOptions: OptionSet {
        let rawValue: Int
        static let withoutChanges = ReadingOptions(rawValue: 1)
        static let forUploading = ReadingOptions(rawValue: 2)
    }

    struct WritingOptions: OptionSet {
        let rawValue: Int
        static let forReplacing = WritingOptions(rawValue: 1)
        static let forDeleting = WritingOptions(rawValue: 2)
    }
}

/// Apple's Dispatch makes a queue a TaskExecutor (`withTaskExecutorPreference(queue)`); Android's
/// does not yet. This is that conformance: each job runs on the queue.
nonisolated extension DispatchQueue: @retroactive TaskExecutor {
    public func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedTaskExecutor()
        async { job.runSynchronously(on: executor) }
    }
}

/// Android reports battery saver and thermal throttling through system services this build
/// does not read, so the skins see a device at rest.
nonisolated extension ProcessInfo {
    enum ThermalState: Int {
        case nominal
        case fair
        case serious
        case critical
    }

    var isLowPowerModeEnabled: Bool { false }
    var thermalState: ThermalState { .nominal }

    static let thermalStateDidChangeNotification = Notification.Name("ProcessInfoThermalStateDidChange")
}

nonisolated extension Notification.Name {
    static let NSProcessInfoPowerStateDidChange = Notification.Name("NSProcessInfoPowerStateDidChange")
}

/// DateComponentsFormatter for the durations the app formats ("3h 10m", "1:05:00"), which
/// swift-corelibs-foundation does not implement.
final nonisolated class AndroidDateComponentsFormatter {
    enum UnitsStyle { case positional, abbreviated, short, full, spellOut, brief }
    enum ZeroFormattingBehavior { case `default`, dropLeading, dropMiddle, dropTrailing, dropAll, pad }

    var allowedUnits: NSCalendar.Unit = [.hour, .minute, .second]
    var unitsStyle: UnitsStyle = .positional
    var maximumUnitCount = 0
    var zeroFormattingBehavior: ZeroFormattingBehavior = .default

    func string(from interval: TimeInterval) -> String? {
        var remaining = Int(abs(interval).rounded())
        var parts: [(Int, String)] = []
        for (unit, seconds, suffix) in [(NSCalendar.Unit.day, 86400, "d"), (.hour, 3600, "h"), (.minute, 60, "m"), (.second, 1, "s")]
            where allowedUnits.contains(unit) {
            parts.append((remaining / seconds, suffix))
            remaining %= seconds
        }
        if unitsStyle == .positional {
            let values = parts.map(\.0)
            guard let first = values.first else { return nil }
            return ([String(first)] + values.dropFirst().map { String(format: "%02d", $0) }).joined(separator: ":")
        }
        var shown = parts.filter { $0.0 != 0 }
        if shown.isEmpty, let last = parts.last { shown = [last] }
        if maximumUnitCount > 0 { shown = Array(shown.prefix(maximumUnitCount)) }
        return shown.map { "\($0.0)\($0.1)" }.joined(separator: " ")
    }

    func string(from start: Date, to end: Date) -> String? {
        string(from: end.timeIntervalSince(start))
    }
}

extension UserDefaults {
    /// AndroidUserDefaults marks `stringArray(forKey:)` unavailable; the stored value is the array.
    nonisolated func androidStringArray(forKey key: String) -> [String]? {
        object(forKey: key) as? [String]
    }
}

/// `Measurement.formatted(.measurement(...))`, which Android's Foundation does not implement:
/// the value in the style's number format, then the unit's symbol.
nonisolated struct AndroidMeasurementFormat {
    enum Width { case wide, abbreviated, narrow }
    enum Usage { case asProvided, general, person, food, road, liquid }

    let numberStyle: FloatingPointFormatStyle<Double>

    static func measurement(
        width _: Width = .abbreviated, usage _: Usage = .general,
        numberFormatStyle: FloatingPointFormatStyle<Double> = .number,
    ) -> AndroidMeasurementFormat {
        AndroidMeasurementFormat(numberStyle: numberFormatStyle)
    }
}

nonisolated extension Measurement where UnitType: Dimension {
    func formatted(_ format: AndroidMeasurementFormat) -> String {
        "\(value.formatted(format.numberStyle)) \(unit.symbol)"
    }
}
