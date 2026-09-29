// `String(localized:)` over Skip's LocalizedStringResource (the app module aliases the name to
// AndroidLocalizedStringResource). A resource's key is the pattern Xcode extracted into
// Localizable.xcstrings, so the lookup finds the same entry the iOS build shows.

import Foundation
import SkipFuse

nonisolated extension String {
    typealias LocalizationValue = LocalizedStringResource

    init(localized resource: LocalizedStringResource, comment _: StaticString? = nil) {
        let format = AndroidResources.bundle.localizedString(forKey: resource.key, value: nil, table: resource.table)
        let arguments = resource.defaultValue.values.map { $0 as? CVarArg ?? String(describing: $0) }
        self = arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }

    init(localized key: String, defaultValue: String? = nil, table: String? = nil, comment _: StaticString? = nil) {
        self = AndroidResources.bundle.localizedString(forKey: key, value: defaultValue, table: table)
    }
}

/// Markdown source as the text it renders: emphasis markers and link syntax removed.
nonisolated func androidPlainMarkdown(_ markdown: String) -> String {
    var text = markdown
    text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
    for marker in ["**", "__", "*", "_", "`"] {
        text = text.replacingOccurrences(of: marker, with: "")
    }
    return text
}
