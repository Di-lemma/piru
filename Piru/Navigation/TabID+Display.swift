import Foundation

/// The tab bar's label for each slot, shared by the bar and Settings ▸ Tabs so
/// the two can never disagree. Pinned screens reuse the title their pushed
/// screen already carries.
extension TabID {
    var title: LocalizedStringResource {
        switch self {
        case let .stock(tab): tab.title
        case let .pinned(screen): screen.title
        }
    }

    var systemImage: String {
        switch self {
        case let .stock(tab): tab.systemImage
        case let .pinned(screen): screen.systemImage
        }
    }
}

extension AppTab {
    var title: LocalizedStringResource {
        switch self {
        case .journal: "Journal"
        case .library: "Library"
        case .tools: "Tools"
        case .insights: "Insights"
        case .search: "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .journal: "book"
        case .library: "books.vertical"
        case .tools: "wrench.and.screwdriver"
        case .insights: "chart.line.uptrend.xyaxis"
        case .search: "magnifyingglass"
        }
    }
}

extension PinnedScreen {
    var title: LocalizedStringResource {
        switch self {
        case let .tool(tool): tool.name
        case let .insight(insight):
            switch insight {
            case .adherence: "Adherence"
            case .usage: "Usage"
            case .tolerance: "Modeled Tolerance"
            case .inSystem, .bodyLoad, .steadyStateProjection: "In Your Body"
            case .receptorLoad: "Receptor Load"
            case .hormoneLevels: "Hormone Levels"
            case .patterns: "Patterns"
            case .feltPatterns: "Did it work?"
            case .reports: "Reports"
            }
        case .insightGroup(.inYourBody): "In Your Body"
        case .insightGroup(.toleranceReceptors): "Modeled Tolerance & Receptors"
        case .myMeds: "My Meds"
        case .timeline: "Timeline"
        case .dataStorage: "Data & Backup"
        }
    }

    var systemImage: String {
        switch self {
        case let .tool(tool): tool.icon
        case let .insight(insight): insight.icon
        case .insightGroup(.inYourBody): "waveform.path.ecg"
        case .insightGroup(.toleranceReceptors): "chart.line.downtrend.xyaxis"
        case .myMeds: "pills"
        case .timeline: "calendar.day.timeline.left"
        case .dataStorage: "externaldrive"
        }
    }
}
