import Foundation
import Observation
import SwiftUI

/// Which tabs the bar shows, in order. Search is kept apart because the system
/// always draws the `.search`-role tab last.
nonisolated struct TabLayout: Equatable {
    /// Tabs besides Search, in bar order.
    var tabs: [TabID]
    var showsSearch: Bool

    /// Four plus Search keeps the iPhone bar from overflowing into "More".
    static let maxTabs = 4

    static let `default` = TabLayout(tabs: [.journal, .library, .tools, .insights], showsSearch: true)

    /// Every tab in the bar, Search last.
    var visible: [TabID] {
        showsSearch ? tabs + [.search] : tabs
    }

    /// The tab whose root stands in for the Journal root: where the first-run
    /// "log a dose" tip anchors. Journal while it is shown, else the first tab.
    var accessoryHome: TabID {
        tabs.contains(.journal) ? .journal : tabs.first ?? .search
    }

    /// Duplicates, a misplaced Search, unpickable screens and anything past
    /// the cap are dropped; a layout with no tab besides Search becomes the
    /// default.
    func normalized() -> TabLayout {
        var seen: Set<TabID> = []
        var showsSearch = showsSearch
        var result: [TabID] = []
        for tab in tabs {
            if tab == .search {
                showsSearch = true
                continue
            }
            if case let .pinned(screen) = tab, !PinnedScreen.pickable.contains(screen) { continue }
            guard seen.insert(tab).inserted else { continue }
            result.append(tab)
        }
        result = Array(result.prefix(Self.maxTabs))
        guard !result.isEmpty else { return .default }
        return TabLayout(tabs: result, showsSearch: showsSearch)
    }

    /// The persisted form: storage keys, Search last when shown.
    var storageKeys: [String] {
        visible.map(\.storageKey)
    }

    /// Unknown keys (a screen a later build removed) are skipped rather than
    /// failing the whole layout.
    init(storageKeys: [String]) {
        let ids = storageKeys.compactMap(TabID.init(storageKey:))
        self.init(tabs: ids.filter { $0 != .search }, showsSearch: ids.contains(.search))
    }

    init(tabs: [TabID], showsSearch: Bool) {
        self.tabs = tabs
        self.showsSearch = showsSearch
    }
}

/// The user's tab bar (Settings ▸ Tabs), persisted as an array of storage keys.
/// Every mutation keeps the layout within the cap and with at least one tab
/// besides Search.
@Observable @MainActor
final class TabLayoutStore {
    static let shared = TabLayoutStore()

    nonisolated static let layoutKey = "tabLayout"

    @ObservationIgnored
    private let defaults: UserDefaults

    /// Set while a tour captures the stock bar; the user's layout is neither
    /// shown nor overwritten meanwhile.
    @ObservationIgnored
    private var ephemeral = false

    private(set) var layout: TabLayout {
        didSet {
            guard !ephemeral, layout != oldValue else { return }
            defaults.set(layout.storageKeys, forKey: Self.layoutKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layout = Self.load(from: defaults)
    }

    private static func load(from defaults: UserDefaults) -> TabLayout {
        guard let keys = defaults.stringArray(forKey: layoutKey) else { return .default }
        return TabLayout(storageKeys: keys).normalized()
    }

    /// Re-reads the layout after an import rewrote it.
    func reloadFromDefaults() {
        guard !ephemeral else { return }
        let stored = Self.load(from: defaults)
        if stored != layout { layout = stored }
    }

    // MARK: Queries

    var canAddTab: Bool {
        layout.tabs.count < TabLayout.maxTabs
    }

    /// Removing is refused for the last tab besides Search.
    var canRemove: Bool {
        layout.tabs.count > 1
    }

    /// Stock tabs not in the bar, in stock order.
    var addableStockTabs: [TabID] {
        [TabID.journal, .library, .tools, .insights].filter { !layout.tabs.contains($0) }
    }

    /// Pinnable screens not in the bar, in picker order.
    var addableScreens: [PinnedScreen] {
        PinnedScreen.pickable.filter { !layout.tabs.contains(.pinned($0)) }
    }

    // MARK: Mutations

    func add(_ tab: TabID) {
        guard canAddTab, tab != .search, !layout.tabs.contains(tab) else { return }
        layout.tabs.append(tab)
    }

    func remove(atOffsets offsets: IndexSet) {
        guard layout.tabs.count - offsets.count >= 1 else { return }
        layout.tabs.remove(atOffsets: offsets)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        layout.tabs.move(fromOffsets: source, toOffset: destination)
    }

    func setShowsSearch(_ shows: Bool) {
        layout.showsSearch = shows
    }

    func reset() {
        layout = .default
    }

    /// Shows `override` without persisting it, or restores the stored layout
    /// when `nil`. For the screenshot and route tours, which must capture the
    /// stock bar whatever the device's own layout is.
    func setEphemeral(_ override: TabLayout?) {
        if let override {
            ephemeral = true
            layout = override
        } else {
            ephemeral = false
            let stored = Self.load(from: defaults)
            ephemeral = true
            layout = stored
            ephemeral = false
        }
    }
}
