// Environment values SkipFuseUI marks unavailable, under names android/substitutions.txt
// points the shared code at.

import SwiftUI

private struct DifferentiateWithoutColorKey: EnvironmentKey {
    /// Android has no "Differentiate Without Color" setting, so it is never on.
    static let defaultValue = false
}

private struct DynamicTypeSizeKey: EnvironmentKey {
    /// Compose scales text by the system font scale itself, so layout reads the default size.
    static let defaultValue = DynamicTypeSize.large
}

private struct DisplayScaleKey: EnvironmentKey {
    /// A typical phone density; the value sizes offscreen textures, which Compose rescales.
    static let defaultValue: CGFloat = 3
}

private struct IsPresentedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var androidDisplayScale: CGFloat {
        get { self[DisplayScaleKey.self] }
        set { self[DisplayScaleKey.self] = newValue }
    }

    var androidIsPresented: Bool {
        get { self[IsPresentedKey.self] }
        set { self[IsPresentedKey.self] = newValue }
    }

    var androidDynamicTypeSize: DynamicTypeSize {
        get { self[DynamicTypeSizeKey.self] }
        set { self[DynamicTypeSizeKey.self] = newValue }
    }

    var androidDifferentiateWithoutColor: Bool {
        get { self[DifferentiateWithoutColorKey.self] }
        set { self[DifferentiateWithoutColorKey.self] = newValue }
    }
}
