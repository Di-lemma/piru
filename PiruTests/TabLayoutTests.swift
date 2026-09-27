import Foundation
import Testing
@testable import Piru

private func isolatedDefaults() -> UserDefaults {
    let suite = "TabLayoutTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private func link(_ string: String) -> DeepLinkOutcome? {
    URL(string: string).flatMap(DeepLink.decode)
}

// MARK: - Identity

@Suite("TabID")
struct TabIDTests {
    @Test
    func `Every stock tab and pickable screen round-trips its storage key`() {
        let all = AppTab.allCases.map(TabID.stock) + PinnedScreen.pickable.map(TabID.pinned)
        for tab in all {
            #expect(TabID(storageKey: tab.storageKey) == tab)
        }
        #expect(Set(all.map(\.storageKey)).count == all.count)
    }

    @Test
    func `A stock tab's key is its AppTab raw value`() {
        #expect(TabID.tools.storageKey == "tools")
        #expect(TabID(storageKey: "insights") == .insights)
    }

    @Test(arguments: ["", "tool.", "tool.effectSandbox", "insight.nope", "myMeds.extra", "banana"])
    func `Unknown keys decode to nil`(key: String) {
        #expect(TabID(storageKey: key) == nil)
    }

    @Test
    func `Codes as a single string, and as a JSON object key`() throws {
        let tab = TabID.pinned(.tool(.inventory))
        let data = try JSONEncoder().encode(tab)
        #expect(String(bytes: data, encoding: .utf8) == "\"tool.inventory\"")
        #expect(try JSONDecoder().decode(TabID.self, from: data) == tab)

        let paths: [TabID: [PushRoute]] = [.journal: [.timeline], tab: []]
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(paths))
        #expect(object is [String: Any])
        #expect(try JSONDecoder().decode([TabID: [PushRoute]].self, from: JSONEncoder().encode(paths)) == paths)
    }
}

@Suite("PinnedScreen")
struct PinnedScreenTests {
    @Test
    func `Every pickable screen round-trips through its route`() {
        for screen in PinnedScreen.pickable {
            #expect(PinnedScreen(route: screen.route) == screen)
        }
    }

    @Test
    func `Routes showing the same screen collapse onto one pin`() {
        #expect(PinnedScreen(route: .comedownGuide) == .tool(.recovery))
        #expect(PinnedScreen(route: .insight(.inSystem)) == .insightGroup(.inYourBody))
        #expect(PinnedScreen(route: .insight(.bodyLoad)) == .insightGroup(.inYourBody))
        #expect(PinnedScreen(route: .insight(.steadyStateProjection)) == .insightGroup(.inYourBody))
    }

    @Test
    func `Routes that are not a screen of their own cannot be pinned`() {
        #expect(PinnedScreen(route: .session(id: UUID())) == nil)
        #expect(PinnedScreen(route: .substance(name: "LSD")) == nil)
        #expect(PinnedScreen(route: .libraryFavorites) == nil)
    }
}

// MARK: - Layout

@Suite("TabLayout")
struct TabLayoutTests {
    @Test
    func `Normalizing drops duplicates, unknowns and overflow, and moves Search last`() {
        let raw = TabLayout(storageKeys: [
            "journal", "search", "journal", "tool.inventory", "nope", "timeline", "insights", "library",
        ])
        let layout = raw.normalized()
        #expect(layout.tabs == [.journal, .pinned(.tool(.inventory)), .pinned(.timeline), .insights])
        #expect(layout.showsSearch)
        #expect(layout.visible.last == .search)
    }

    @Test(arguments: [[String](), ["search"], ["nope"]])
    func `A layout with no tab besides Search becomes the default`(keys: [String]) {
        #expect(TabLayout(storageKeys: keys).normalized() == .default)
    }

    @Test
    func `Unpickable pins are dropped`() {
        let layout = TabLayout(tabs: [.library, .pinned(.insight(.inSystem))], showsSearch: false).normalized()
        #expect(layout.tabs == [.library])
    }

    @Test
    func `The accessory's home is Journal while shown, else the first tab`() {
        #expect(TabLayout(tabs: [.library, .journal], showsSearch: true).accessoryHome == .journal)
        #expect(TabLayout(tabs: [.pinned(.myMeds), .library], showsSearch: true).accessoryHome == .pinned(.myMeds))
    }
}

@MainActor
@Suite("TabLayoutStore")
struct TabLayoutStoreTests {
    @Test
    func `A fresh store has the default layout`() {
        #expect(TabLayoutStore(defaults: isolatedDefaults()).layout == .default)
    }

    @Test
    func `Edits persist to defaults and reload in a new store`() {
        let defaults = isolatedDefaults()
        let store = TabLayoutStore(defaults: defaults)
        store.remove(atOffsets: [2]) // Tools
        store.add(.pinned(.tool(.inventory)))
        store.move(fromOffsets: [3], toOffset: 0)
        store.setShowsSearch(false)

        let expected = TabLayout(tabs: [.pinned(.tool(.inventory)), .journal, .library, .insights], showsSearch: false)
        #expect(store.layout == expected)
        #expect(defaults.stringArray(forKey: TabLayoutStore.layoutKey) == ["tool.inventory", "journal", "library", "insights"])
        #expect(TabLayoutStore(defaults: defaults).layout == expected)
    }

    @Test
    func `Adding is refused at the cap and for a tab already in the bar`() {
        let store = TabLayoutStore(defaults: isolatedDefaults())
        #expect(!store.canAddTab)
        store.add(.pinned(.timeline))
        #expect(store.layout == .default)

        store.remove(atOffsets: [0])
        store.add(.library)
        store.add(.search)
        #expect(store.layout.tabs == [.library, .tools, .insights])
    }

    @Test
    func `The last tab besides Search cannot be removed`() {
        let store = TabLayoutStore(defaults: isolatedDefaults())
        store.remove(atOffsets: [0, 1, 2, 3])
        #expect(store.layout == .default)
        store.remove(atOffsets: [0, 1, 2])
        #expect(store.layout.tabs == [.insights])
        #expect(!store.canRemove)
        store.remove(atOffsets: [0])
        #expect(store.layout.tabs == [.insights])
    }

    @Test
    func `Reset restores the default`() {
        let store = TabLayoutStore(defaults: isolatedDefaults())
        store.remove(atOffsets: [0])
        store.setShowsSearch(false)
        store.reset()
        #expect(store.layout == .default)
    }

    @Test
    func `An ephemeral layout is never written, and clearing it restores the stored one`() {
        let defaults = isolatedDefaults()
        let store = TabLayoutStore(defaults: defaults)
        store.remove(atOffsets: [0])
        let stored = defaults.stringArray(forKey: TabLayoutStore.layoutKey)

        store.setEphemeral(.default)
        #expect(store.layout == .default)
        #expect(defaults.stringArray(forKey: TabLayoutStore.layoutKey) == stored)

        store.setEphemeral(nil)
        #expect(store.layout.tabs == [.library, .tools, .insights])
        #expect(defaults.stringArray(forKey: TabLayoutStore.layoutKey) == stored)
    }

    @Test
    func `Reloading picks up a layout an import wrote`() {
        let defaults = isolatedDefaults()
        let store = TabLayoutStore(defaults: defaults)
        defaults.set(["timeline", "journal"], forKey: TabLayoutStore.layoutKey)
        store.reloadFromDefaults()
        #expect(store.layout == TabLayout(tabs: [.pinned(.timeline), .journal], showsSearch: false))
    }
}

// MARK: - Routing

@Suite("TabRouting")
struct TabRoutingTests {
    private let stock = TabLayout.default.visible

    @Test
    func `A pinned screen wins, even over its visible home tab`() {
        let visible = stock.dropLast() + [.pinned(.tool(.inventory))]
        #expect(TabRouting.target(for: .tool(.inventory), home: .tools, visible: Array(visible)) == .pinned(.pinned(.tool(.inventory))))
    }

    @Test
    func `A pin is found through a route that shows the same screen`() {
        let visible: [TabID] = [.journal, .pinned(.insightGroup(.inYourBody))]
        #expect(TabRouting.target(for: .insight(.bodyLoad), home: .insights, visible: visible) == .pinned(.pinned(.insightGroup(.inYourBody))))
    }

    @Test
    func `A visible home tab is used when nothing is pinned`() {
        #expect(TabRouting.target(for: .tool(.inventory), home: .tools, visible: stock) == .home(.tools))
    }

    @Test
    func `A hidden home tab falls back to the current tab`() {
        let visible: [TabID] = [.library, .insights]
        #expect(TabRouting.target(for: .session(id: UUID()), home: .journal, visible: visible) == .current)
        #expect(TabRouting.target(for: nil, home: nil, visible: visible) == .current)
    }
}

// MARK: - Navigator

@MainActor
@Suite("AppNavigator with a custom tab bar")
struct AppNavigatorTabLayoutTests {
    private func make(
        _ tabs: [TabID],
        showsSearch: Bool = true,
        selectedTab: TabID? = nil,
        persisted: String? = nil,
    ) -> (AppNavigator, TabLayoutStore) {
        let defaults = isolatedDefaults()
        defaults.set(TabLayout(tabs: tabs, showsSearch: showsSearch).storageKeys, forKey: TabLayoutStore.layoutKey)
        if let persisted { defaults.set(persisted, forKey: "AppNavigator.selectedTab") }
        let layout = TabLayoutStore(defaults: defaults)
        return (AppNavigator(selectedTab: selectedTab, storage: defaults, layout: layout), layout)
    }

    @Test
    func `A persisted tab no longer in the bar falls back to the first tab`() {
        let (nav, _) = make([.library, .insights], persisted: "journal")
        #expect(nav.selectedTab == .library)
        let (nav2, _) = make([.library], persisted: "tool.effectSandbox")
        #expect(nav2.selectedTab == .library)
    }

    @Test
    func `A persisted pinned tab restores`() {
        let (nav, _) = make([.library, .pinned(.timeline)], persisted: "timeline")
        #expect(nav.selectedTab == .pinned(.timeline))
    }

    @Test
    func `Reconcile reselects and drops the stacks of removed tabs`() {
        let (nav, _) = make([.journal, .library], selectedTab: .journal)
        nav.push(.timeline, in: .journal)
        nav.push(.substance(name: "LSD"), in: .library)
        nav.reconcile(visible: [.library, .search])
        #expect(nav.selectedTab == .library)
        #expect(nav.path(for: .journal).isEmpty)
        #expect(nav.path(for: .library) == [.substance(name: "LSD")])
    }

    @Test
    func `A link to a pinned screen lands on its tab at the root`() throws {
        let (nav, _) = make([.journal, .tools, .pinned(.tool(.inventory))], selectedTab: .journal)
        nav.push(.substance(name: "LSD"), in: .pinned(.tool(.inventory)))
        let outcome = try #require(link("piru://tool/inventory"))
        nav.apply(outcome)
        #expect(nav.selectedTab == .pinned(.tool(.inventory)))
        #expect(nav.path(for: .pinned(.tool(.inventory))).isEmpty)
        #expect(nav.path(for: .tools).isEmpty)
    }

    @Test
    func `A link whose home is hidden appends to the current tab`() throws {
        let id = UUID()
        let (nav, _) = make([.library, .insights], selectedTab: .library)
        nav.push(.substance(name: "LSD"))
        let outcome = try #require(link("piru://session/\(id.uuidString)"))
        nav.apply(outcome)
        #expect(nav.selectedTab == .library)
        #expect(nav.path(for: .library) == [.substance(name: "LSD"), .session(id: id)])

        // The same link again doesn't stack a duplicate.
        nav.apply(outcome)
        #expect(nav.path(for: .library) == [.substance(name: "LSD"), .session(id: id)])
    }

    @Test
    func `A tab-only link to a hidden tab changes nothing`() throws {
        let (nav, _) = make([.library, .insights], selectedTab: .insights)
        let outcome = try #require(link("piru://journal"))
        nav.apply(outcome)
        #expect(nav.selectedTab == .insights)
    }

    @Test
    func `A journal sheet with Journal hidden opens over the current tab`() throws {
        let (nav, _) = make([.library, .insights], selectedTab: .insights)
        let outcome = try #require(link("piru://day"))
        nav.apply(outcome)
        #expect(nav.selectedTab == .insights)
        #expect(nav.sheetStack == [.sessionDetail])
    }

    @Test
    func `Opening a session reveals it on a pinned tab's stack`() {
        let id = UUID()
        let (nav, _) = make([.library, .pinned(.timeline)], selectedTab: .library)
        nav.push(.session(id: id), in: .pinned(.timeline))
        nav.push(.substance(name: "LSD"), in: .pinned(.timeline))
        nav.revealOrPresentSessionDetail(currentSessionID: id)
        #expect(nav.selectedTab == .pinned(.timeline))
        #expect(nav.path(for: .pinned(.timeline)) == [.session(id: id)])
        #expect(nav.sheetStack.isEmpty)
    }

    @Test
    func `Open lands on the pin, the home tab, or the current tab`() {
        let (pinned, _) = make([.journal, .pinned(.myMeds)], selectedTab: .journal)
        pinned.open(.myMeds, home: .journal)
        #expect(pinned.selectedTab == .pinned(.myMeds))
        #expect(pinned.path(for: .journal).isEmpty)

        let (home, _) = make([.library, .tools], selectedTab: .library)
        home.open(.tool(.inventory), home: .tools)
        #expect(home.selectedTab == .tools)
        #expect(home.path(for: .tools) == [.tool(.inventory)])

        let (current, _) = make([.library, .insights], selectedTab: .insights)
        current.open(.tool(.inventory), home: .tools)
        #expect(current.selectedTab == .insights)
        #expect(current.path(for: .insights) == [.tool(.inventory)])
    }
}

// MARK: - Deep link encoding

@Suite("DeepLink encoding of pinned tabs")
struct PinnedTabDeepLinkTests {
    @Test
    func `A pinned tab at its root encodes its screen, with no tab override`() {
        let url = DeepLink.encode(NavigatorSnapshot(selectedTab: .pinned(.tool(.inventory))))
        #expect(url?.absoluteString == "piru://tool/inventory")
    }

    @Test
    func `A pinned screen with no URL form encodes to nil`() {
        #expect(DeepLink.encode(NavigatorSnapshot(selectedTab: .pinned(.timeline))) == nil)
    }

    @Test
    func `A sheet over a pinned tab carries no tab override`() {
        let url = DeepLink.encode(NavigatorSnapshot(selectedTab: .pinned(.timeline), sheetStack: [.settings]))
        #expect(url?.absoluteString == "piru://settings")
    }
}
