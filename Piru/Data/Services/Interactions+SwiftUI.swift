import SwiftUI

nonisolated extension InteractionSeverity {
    /// Mark colour — fills, bands, dots. Text uses ``labelColor``.
    ///
    /// `@MainActor` because Xcode's generated asset symbols are, under the
    /// project's `-default-isolation MainActor`. The raw system hues this
    /// replaced were nonisolated, so this is a real (small) constraint added in
    /// exchange for the values being gated and centrally defined.
    @MainActor var color: Color {
        switch self {
        case .caution: .Severity.Caution.accent
        case .unsafe: .Severity.Unsafe.accent
        case .dangerous: .Severity.Dangerous.accent
        }
    }

    /// Legible text variant, gated at WCAG AA against the card *and* against
    /// this severity's own tinted fill.
    ///
    /// ``color`` is a fill value: as small text it measured 1.39:1 for
    /// `.caution` and 3.27:1 for `.dangerous`.
    ///
    /// This is a three-step *scale*, not three `semantic/*` lookups. `.unsafe`
    /// sits between caution and danger, and the four-level semantic ladder has
    /// no middle tier — folding it into `danger` would erase a distinction the
    /// app deliberately makes. It kept failing at 2.12:1 until the ladder got
    /// its own scale.
    @MainActor var labelColor: Color {
        switch self {
        case .caution: .Severity.Caution.text
        case .unsafe: .Severity.Unsafe.text
        case .dangerous: .Severity.Dangerous.text
        }
    }
}
