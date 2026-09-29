// What UserNotifications gives the iOS build beyond SkipFuseUI's bridge: typed pending
// requests, the interruption level and relevance (Android sets these per notification
// channel rather than per notification), and actionable categories, which register nothing:
// an Android notification action needs a Kotlin broadcast receiver this build does not ship.

import SwiftUI

nonisolated enum UNNotificationInterruptionLevel: Int {
    case passive, active, timeSensitive, critical
}

nonisolated extension UNMutableNotificationContent {
    var interruptionLevel: UNNotificationInterruptionLevel {
        get { .active }
        set {}
    }

    var relevanceScore: Double {
        get { 0 }
        set {}
    }
}

struct UNNotificationActionOptions: OptionSet {
    let rawValue: Int
    static let authenticationRequired = UNNotificationActionOptions(rawValue: 1)
    static let destructive = UNNotificationActionOptions(rawValue: 2)
    static let foreground = UNNotificationActionOptions(rawValue: 4)
}

struct UNNotificationCategoryOptions: OptionSet {
    let rawValue: Int
    static let customDismissAction = UNNotificationCategoryOptions(rawValue: 1)
    static let hiddenPreviewsShowTitle = UNNotificationCategoryOptions(rawValue: 2)
}

nonisolated final class UNNotificationAction: Hashable {
    let identifier: String
    let title: String

    init(identifier: String, title: String, options: UNNotificationActionOptions = [], icon: Any? = nil) {
        self.identifier = identifier
        self.title = title
    }

    static func == (lhs: UNNotificationAction, rhs: UNNotificationAction) -> Bool { lhs.identifier == rhs.identifier }
    func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
}

nonisolated final class UNNotificationCategory: Hashable {
    let identifier: String

    init(identifier: String, actions: [UNNotificationAction], intentIdentifiers: [String], options: UNNotificationCategoryOptions = []) {
        self.identifier = identifier
    }

    static func == (lhs: UNNotificationCategory, rhs: UNNotificationCategory) -> Bool { lhs.identifier == rhs.identifier }
    func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
}

nonisolated extension UNUserNotificationCenter {
    /// SkipFuseUI returns the pending requests untyped.
    @concurrent func androidPendingNotificationRequests() async -> [UNNotificationRequest] {
        await pendingNotificationRequests().compactMap { $0 as? UNNotificationRequest }
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}

    func add(_ request: UNNotificationRequest, withCompletionHandler completion: (@Sendable (Error?) -> Void)? = nil) {
        // The center is the process-wide singleton, so handing it to the task shares nothing new.
        nonisolated(unsafe) let center = self
        Task {
            do {
                try await center.add(request)
                completion?(nil)
            } catch {
                completion?(error)
            }
        }
    }

    func getPendingNotificationRequests(completionHandler: @escaping @Sendable ([UNNotificationRequest]) -> Void) {
        nonisolated(unsafe) let center = self
        Task {
            completionHandler(await center.androidPendingNotificationRequests())
        }
    }
}

/// A repeating calendar reminder on Android. Skip's calendar trigger carries its
/// DateComponents as `Any`, which the bridge cannot hand to Kotlin (a fatal error on
/// schedule), so the reminder is the next matching moment as a one-shot interval trigger.
/// The routine reminders are rescheduled whenever the app runs, which carries it forward.
enum AndroidCalendarTrigger {
    static func make(dateMatching components: DateComponents, repeats: Bool) -> UNNotificationTrigger {
        let next = Calendar.current.nextDate(after: .now, matching: components, matchingPolicy: .nextTime)
            ?? .now.addingTimeInterval(60)
        return UNTimeIntervalNotificationTrigger(timeInterval: max(1, next.timeIntervalSinceNow), repeats: false)
    }
}
