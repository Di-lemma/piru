import SwiftUI

/// Settings ▸ Tabs: which tabs the bar shows, in what order, and what they
/// are called. Any stock tab can go, any tool, insight or the Timeline can
/// take a slot of its own, and any of them can be renamed.
struct TabsSettingsView: View {
    @State private var showsPicker = false
    /// The tab being renamed, and the name being typed.
    @State private var renaming: TabID?
    @State private var draft = ""
    @State private var store = TabLayoutStore.shared

    var body: some View {
        List {
            Group {
                TabBarSection(onAdd: { showsPicker = true }, onRename: startRenaming)
                SearchTabSection(onRename: startRenaming)
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
        .alert("Rename Tab", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Tab name", text: $draft)
            Button("Save") {
                if let renaming { store.rename(renaming, to: draft) }
            }
            if let renaming, store.name(for: renaming) != nil {
                Button("Use Original Name") { store.rename(renaming, to: "") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Leave it empty to use the original name.")
        }
    }

    private func startRenaming(_ tab: TabID) {
        draft = store.name(for: tab) ?? String(localized: tab.title)
        renaming = tab
    }
}

/// The tabs in the bar, reorderable and removable, plus an add row while a
/// slot is free.
private struct TabBarSection: View {
    /// A button, not a `NavigationLink`: in the list's permanent edit mode a
    /// link row takes no taps.
    let onAdd: () -> Void
    let onRename: (TabID) -> Void
    @State private var store = TabLayoutStore.shared

    var body: some View {
        Section {
            ForEach(store.layout.tabs) { tab in
                HStack(spacing: 10) {
                    TabLabel(tab: tab)
                    RenameButton { onRename(tab) }
                    Spacer(minLength: 0)
                }
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
    let onRename: (TabID) -> Void
    @State private var store = TabLayoutStore.shared

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.layout.showsSearch },
                set: { store.setShowsSearch($0) },
            )) {
                HStack(spacing: 10) {
                    TabLabel(tab: .search)
                    RenameButton { onRename(.search) }
                }
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

/// A tab as the bar labels it, with its own title underneath once renamed,
/// so a renamed tab never loses what it is.
private struct TabLabel: View {
    let tab: TabID
    @State private var store = TabLayoutStore.shared

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                store.label(for: tab)
                if store.name(for: tab) != nil {
                    Text(tab.title)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        } icon: {
            Image(systemName: tab.systemImage)
        }
    }
}

/// Right beside the tab's name, and meant to be seen: a tinted capsule rather
/// than a bare icon. Borderless, so it takes taps in the list's edit mode.
private struct RenameButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Built by hand rather than a `Label`: inside the Search row's
            // `Toggle`, a label's icon and title are laid out apart.
            HStack(spacing: 5) {
                Image(systemName: "pencil")
                Text("Rename")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.accent.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.borderless)
    }
}

#Preview {
    NavigationStack { TabsSettingsView() }
}
