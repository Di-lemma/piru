// Piru/Utilities/PlatformCompat.swift for Android, where the upstream file's #if branches
// (UIKit, else AppKit) have no case. It follows the file's iOS branches wherever SkipFuseUI
// provides the same API, which it does for most of UIKit's pasteboard, color and image
// surface. exclude.txt drops the upstream file; a shim added there fails this build until
// it is added here.

import SwiftUI

typealias PlatformImage = UIImage
typealias PlatformView = AnyObject

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

extension ImageRenderer {
    /// Android renders no offscreen images (Android/SwiftUI/SwiftUI+Android.swift).
    var platformImage: PlatformImage? { nil }
}

enum PlatformPasteboard {
    static func copy(_ string: String) {
        UIPasteboard.general.string = string
    }

    /// SkipFuseUI's pasteboard carries text only; an image or a file has no clipboard path here.
    static func copy(image: UIImage) {}

    static func copy(data: Data, type: String) {}
}

enum PlatformHaptics {
    static func success() {}
    static func impact() {}
}

func openPlatformSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        Task { await UIApplication.shared.open(url) }
    }
}

func openNotificationSettings() {
    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
        Task { await UIApplication.shared.open(url) }
    }
}

/// SkipFuseUI bridges only the system background; the rest are UIKit's definitions written
/// out, translucent grays that read on light and dark alike.
extension Color {
    private static let fillGray = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255)
    private static let labelGray = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255)

    static var platformSystemBackground: Color { Color(.systemBackground) }
    static var platformSecondarySystemBackground: Color { fillGray.opacity(0.10) }
    static var platformSecondarySystemGroupedBackground: Color { fillGray.opacity(0.10) }
    static var platformSecondarySystemFill: Color { fillGray.opacity(0.16) }
    static var platformTertiarySystemFill: Color { fillGray.opacity(0.12) }
    static var platformQuaternaryLabel: Color { labelGray.opacity(0.18) }
    static var platformTertiaryLabel: Color { labelGray.opacity(0.3) }
    static var platformSystemGray: Color { Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255) }
}

extension View {
    func inlineNavigationTitle() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }

    func alwaysVisibleSearch(text: Binding<String>, prompt: Text) -> some View {
        searchable(text: text, prompt: prompt)
    }

    func insetGroupedListStyle() -> some View {
        listStyle(.automatic)
    }

    func wheelPickerStyle() -> some View {
        pickerStyle(.menu)
    }

    func decimalKeyboard() -> some View {
        keyboardType(.decimalPad)
    }

    func neverAutocapitalize() -> some View {
        textInputAutocapitalization(.never)
    }

    func wordsAutocapitalize() -> some View {
        textInputAutocapitalization(.words)
    }

    func permanentEditMode() -> some View {
        self
    }

    func compactListSectionSpacing() -> some View {
        self
    }

    func readableWidth() -> some View {
        self
    }
}

extension ToolbarItemPlacement {
    static var platformTopBarTrailing: ToolbarItemPlacement { .topBarTrailing }
    static var platformTopBarLeading: ToolbarItemPlacement { .topBarLeading }
}
