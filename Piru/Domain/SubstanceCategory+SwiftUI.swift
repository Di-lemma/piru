import SwiftUI

extension SubstanceCategory {
    /// Mark colour for the category badge. Text uses ``labelColor``.
    ///
    /// Nine of these were hand-mixed `Color(red:green:blue:)` literals with **no
    /// dark variant**, so they rendered the same pixel in both appearances.
    /// All 29 now come from the `category` scale in the catalog.
    @MainActor var color: Color {
        switch self {
        case .stimulant: .Category.Stimulant.accent
        case .psychedelic: .Category.Psychedelic.accent
        case .dissociative: .Category.Dissociative.accent
        case .dysdelic: .Category.Dysdelic.accent
        case .deliriant: .Category.Deliriant.accent
        case .opioid: .Category.Opioid.accent
        case .benzodiazepine: .Category.Benzodiazepine.accent
        case .gabapentinoid: .Category.Gabapentinoid.accent
        case .empathogen: .Category.Empathogen.accent
        case .cannabinoid: .Category.Cannabinoid.accent
        case .nootropic: .Category.Nootropic.accent
        case .ampakine: .Category.Ampakine.accent
        case .eugeroic: .Category.Eugeroic.accent
        case .depressant: .Category.Depressant.accent
        case .orexinAntagonist: .Category.OrexinAntagonist.accent
        case .antidepressant: .Category.Antidepressant.accent
        case .antipsychotic: .Category.Antipsychotic.accent
        case .analgesic: .Category.Analgesic.accent
        case .antihistamine: .Category.Antihistamine.accent
        case .cardiovascular: .Category.Cardiovascular.accent
        case .antimicrobial: .Category.Antimicrobial.accent
        case .gastrointestinal: .Category.Gastrointestinal.accent
        case .respiratory: .Category.Respiratory.accent
        case .endocrine: .Category.Endocrine.accent
        case .immunological: .Category.Immunological.accent
        case .supplement: .Category.Supplement.accent
        case .peptide: .Category.Peptide.accent
        case .anticonvulsant: .Category.Anticonvulsant.accent
        case .other: .Category.Other.accent
        }
    }

    /// Legible text variant, gated at WCAG AA against the card *and* against
    /// this category's own tinted fill. The Library badge draws the name in this
    /// colour on a 12% fill of ``color`` — the self-tint pattern, which measured
    /// 2.06:1 for stimulant orange before the scale existed.
    @MainActor var labelColor: Color {
        switch self {
        case .stimulant: .Category.Stimulant.text
        case .psychedelic: .Category.Psychedelic.text
        case .dissociative: .Category.Dissociative.text
        case .dysdelic: .Category.Dysdelic.text
        case .deliriant: .Category.Deliriant.text
        case .opioid: .Category.Opioid.text
        case .benzodiazepine: .Category.Benzodiazepine.text
        case .gabapentinoid: .Category.Gabapentinoid.text
        case .empathogen: .Category.Empathogen.text
        case .cannabinoid: .Category.Cannabinoid.text
        case .nootropic: .Category.Nootropic.text
        case .ampakine: .Category.Ampakine.text
        case .eugeroic: .Category.Eugeroic.text
        case .depressant: .Category.Depressant.text
        case .orexinAntagonist: .Category.OrexinAntagonist.text
        case .antidepressant: .Category.Antidepressant.text
        case .antipsychotic: .Category.Antipsychotic.text
        case .analgesic: .Category.Analgesic.text
        case .antihistamine: .Category.Antihistamine.text
        case .cardiovascular: .Category.Cardiovascular.text
        case .antimicrobial: .Category.Antimicrobial.text
        case .gastrointestinal: .Category.Gastrointestinal.text
        case .respiratory: .Category.Respiratory.text
        case .endocrine: .Category.Endocrine.text
        case .immunological: .Category.Immunological.text
        case .supplement: .Category.Supplement.text
        case .peptide: .Category.Peptide.text
        case .anticonvulsant: .Category.Anticonvulsant.text
        case .other: .Category.Other.text
        }
    }
}
