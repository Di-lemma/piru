import Foundation

/// What was in the stomach when an oral dose was taken. Food slows gastric emptying,
/// and an oral dose absorbs only once it leaves the stomach, so a meal moves the
/// whole acute curve later; for most substances it does little else.
///
/// Three steps, because the literature is binary: food-effect studies compare a
/// fasted arm with one standard high-fat meal (FDA's ~800–1000 kcal breakfast).
/// ``full`` is that meal, ``empty`` is the fasted arm, and ``light`` is the one
/// in-between state people actually report. It is scaled halfway, an
/// interpolation Piru makes, not a measured condition.
enum MealState: String, Codable, CaseIterable, Hashable, Sendable {
    case empty
    case light
    case full

    /// The fraction of a substance's fed-vs-fasted Tmax delay this state applies:
    /// `0` for the fasted arm, `1` for the study meal.
    var fedFraction: Double {
        switch self {
        case .empty: 0
        case .light: 0.5
        case .full: 1
        }
    }

    var label: String {
        switch self {
        case .empty: String(localized: "Empty stomach")
        case .light: String(localized: "Light snack")
        case .full: String(localized: "Full meal")
        }
    }

    /// The shorter word the quick-log chip shows once a state is picked.
    var chipLabel: String {
        switch self {
        case .empty: String(localized: "Fasted")
        case .light: String(localized: "Snack")
        case .full: String(localized: "Meal")
        }
    }

    /// A fill gauge, so the three read as one scale: empty, half, full.
    /// ``unknownSystemImage`` is its dotted outline.
    var systemImage: String {
        switch self {
        case .empty: "circle"
        case .light: "circle.bottomhalf.filled"
        case .full: "circle.fill"
        }
    }

    static let unknownSystemImage = "circle.dashed"
}
