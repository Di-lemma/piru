import SwiftUI

/// Settings ▸ Tabs: which tabs the bar shows and in what order. Any stock tab
/// can go, and any tool, insight or the Timeline can take a slot of its own.
struct TabsSettingsView: View {
    @State private var showsPicker = false

    var body: some View {
        List {
            Group {
                TabBarSection(onAdd: { showsPicker = true })
                SearchTabSection()
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .permanentEditMode()
        .navigationDestination(isPresented: $showsPicker) {
            TabPickerView()
        }
        .navigationTitle("Tabs")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reset") {
                    TabLayoutStore.shared.reset()
                }
            }
        }
    }
}

/// The tabs in the bar, reorderable and removable, plus an add row while a
/// slot is free.
private struct TabBarSection: View {
    /// A button, not a `NavigationLink`: in the list's permanent edit mode a
    /// link row takes no taps.
    let onAdd: () -> Void
    @State private var store = TabLayoutStore.shared

    var body: some View {
        Section {
            ForEach(store.layout.tabs) { tab in
                TabLabel(tab: tab)
            }
            .onMove { source, destination in
                store.move(fromOffsets: source, toOffset: destination)
            }
            .onDelete { offsets in
                store.remove(atOffsets: offsets)
            }
            .deleteDisabled(!store.canRemove)

            if store.canAddTab {
                Button(action: onAdd) {
                    Label("Add a Tab…", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("In the Tab Bar")
                .textCase(nil)
        } footer: {
            if !store.canRemove {
                Text("At least one tab besides Search stays in the bar.")
            } else if !store.canAddTab {
                Text("The tab bar is full. Remove a tab to add another.")
            } else {
                Text("Up to four tabs, plus Search.")
            }
        }
    }
}

private struct SearchTabSection: View {
    @State private var store = TabLayoutStore.shared

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.layout.showsSearch },
                set: { store.setShowsSearch($0) },
            )) {
                TabLabel(tab: .search)
            }
        } footer: {
            Text("Search always sits at the end of the tab bar.")
        }
    }
}

/// Everything not already in the bar, grouped by where it lives today.
private struct TabPickerView: View {
    @State private var store = TabLayoutStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let screens = store.addableScreens
        let tools = screens.filter {
            switch $0 {
            case .tool, .myMeds, .dataStorage: true
            default: false
            }
        }
        let insights = screens.filter {
            switch $0 {
            case .insight, .insightGroup: true
            default: false
            }
        }
        let others = screens.filter { $0 == .timeline }

        List {
            Group {
                PickerSection(title: "Tabs", tabs: store.addableStockTabs, add: add)
                PickerSection(title: "Tools", tabs: tools.map(TabID.pinned), add: add)
                PickerSection(title: "Insights", tabs: insights.map(TabID.pinned), add: add)
                PickerSection(title: "Screens", tabs: others.map(TabID.pinned), add: add)
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle("Add a Tab…")
        .inlineNavigationTitle()
    }

    private func add(_ tab: TabID) {
        store.add(tab)
        dismiss()
    }
}

private struct PickerSection: View {
    let title: LocalizedStringKey
    let tabs: [TabID]
    let add: (TabID) -> Void

    var body: some View {
        if !tabs.isEmpty {
            Section {
                ForEach(tabs) { tab in
                    Button {
                        add(tab)
                    } label: {
                        TabLabel(tab: tab)
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text(title)
                    .textCase(nil)
            }
        }
    }
}

/// A tab as the bar labels it.
private struct TabLabel: View {
    let tab: TabID

    var body: some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(systemName: tab.systemImage)
        }
    }
}

#Preview {
    NavigationStack { TabsSettingsView() }
}
