// Shared/ContrastAwareStyles.swift for Android. Its styles resolve against Increase Contrast
// through a custom ShapeStyle, which SkipFuseUI cannot bridge to Compose; Android has no such
// setting for the app to read, so each is its standard-contrast form.

import SwiftUI

/// `.tertiary` as the upstream type draws it at standard contrast.
typealias LegibleTertiary = Color

extension Color {
    init(strong: Color) {
        self = strong.opacity(0.6)
    }

    nonisolated func legibleOpacity(_ opacity: Double) -> Color {
        self.opacity(opacity)
    }
}

extension ShapeStyle {
    nonisolated func legibleOpacity(_ opacity: Double) -> some ShapeStyle {
        self.opacity(opacity)
    }
}
