// The time zone and content language from Android's own settings (Skip/AndroidPlatform.kt).
// Skip's bootstrap sets TZ to the zone's abbreviation, which Foundation resolves through its
// abbreviation table: CST reads as America/Chicago, IST as Asia/Kolkata. The IANA identifier
// Java reports is exact.

import Foundation
import SkipBridge
import SkipFuse

nonisolated enum AndroidPlatform {
    private static var kotlin: AnyDynamicObject? {
        try? AnyDynamicObject(forStaticsOfClassName: "piru.module.AndroidPlatform")
    }

    /// Points `TimeZone.current` at the device's zone by its identifier. Runs at launch,
    /// before anything reads the zone, and again whenever the device's zone changes.
    static func adoptDeviceTimeZone(_ identifier: String? = nil) {
        guard let identifier = identifier ?? (try? kotlin?.timeZoneID() as String?),
              TimeZone(identifier: identifier) != nil
        else { return }
        setenv("TZ", identifier, 1)
        tzset()
        NSTimeZone.resetSystemTimeZone()
        Logger(subsystem: "piru", category: "platform").info("time zone \(identifier, privacy: .public) → TimeZone.current \(TimeZone.current.identifier, privacy: .public)")
    }

    /// The user's languages, most preferred first.
    static var languageTags: [String] {
        let tags = (try? kotlin?.languageTags() as String?) ?? ""
        return tags.split(separator: ",").map(String.init)
    }
}

extension Bundle {
    /// `preferredLocalizations` on Android: the user's languages the app ships, in the user's
    /// order, as iOS intersects the preferred languages with the bundle's localizations. The
    /// app's localizations are English, Spanish and Chinese; English when none of the user's
    /// languages is among them.
    nonisolated static var androidPreferredLocalizations: [String] {
        let shipped = AndroidPlatform.languageTags.filter { tag in
            let language = tag.lowercased().split(separator: "-").first.map(String.init) ?? ""
            return ["en", "es", "zh"].contains(language)
        }
        return shipped.isEmpty ? ["en"] : shipped
    }
}
