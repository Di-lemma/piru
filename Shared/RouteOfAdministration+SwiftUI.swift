import SwiftUI

extension RouteOfAdministration {
    /// A fixed tint per route — so a route reads the same everywhere (every
    /// "oral" badge is the same colour), independent of the substance's own
    /// colour. Used by the dose-row / detail ROA pills.
    ///
    /// Values live in the design system (`design-system/color/palette-L2.json`,
    /// scale `route`) and resolve from the asset catalog. Hue is preserved from
    /// the hand-tuned table this replaced; only lightness and chroma moved.
    var tintColor: Color {
        switch self {
        case .oral: .Route.Oral.accent
        case .sublingual: .Route.Sublingual.accent
        case .buccal: .Route.Buccal.accent
        case .insufflation: .Route.Insufflation.accent
        case .inhalation: .Route.Inhalation.accent
        case .intravenous: .Route.Intravenous.accent
        case .intramuscular: .Route.Intramuscular.accent
        case .subcutaneous: .Route.Subcutaneous.accent
        case .transdermal: .Route.Transdermal.accent
        case .rectal: .Route.Rectal.accent
        case .other: .Route.Other.accent
        }
    }

    /// Legible text variant for the ~11pt pill label.
    ///
    /// Guarantees ≥4.5:1 contrast against the pill's 0.10-alpha fill in both
    /// light and dark mode. Never raise that fill alpha without re-checking dark
    /// mode: a color on a tint of itself asymptotes toward roughly 4.5:1
    /// regardless of lightness, so the fill alpha itself is load-bearing for
    /// reaching that ratio in dark mode.
    var tintTextColor: Color {
        switch self {
        case .oral: .Route.Oral.text
        case .sublingual: .Route.Sublingual.text
        case .buccal: .Route.Buccal.text
        case .insufflation: .Route.Insufflation.text
        case .inhalation: .Route.Inhalation.text
        case .intravenous: .Route.Intravenous.text
        case .intramuscular: .Route.Intramuscular.text
        case .subcutaneous: .Route.Subcutaneous.text
        case .transdermal: .Route.Transdermal.text
        case .rectal: .Route.Rectal.text
        case .other: .Route.Other.text
        }
    }
}
