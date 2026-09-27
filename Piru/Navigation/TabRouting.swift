/// Where a "land me here" request — a deep link, a notification, a dock
/// shortcut — goes once the user may have pinned, moved or hidden tabs.
nonisolated enum TabRouting {
    enum Target: Equatable {
        /// The destination is pinned as this tab: switch to it at its root.
        case pinned(TabID)
        /// The destination's home tab is shown: switch to it and push there.
        case home(TabID)
        /// Neither: push onto whatever tab is showing.
        case current
    }

    /// A pinned tab wins even over a visible home tab, so a link never opens a
    /// second copy of a screen the user already keeps a tab for.
    static func target(for route: PushRoute?, home: AppTab?, visible: [TabID]) -> Target {
        if let route, let screen = PinnedScreen(route: route), visible.contains(.pinned(screen)) {
            return .pinned(.pinned(screen))
        }
        if let home, visible.contains(.stock(home)) {
            return .home(.stock(home))
        }
        return .current
    }
}
