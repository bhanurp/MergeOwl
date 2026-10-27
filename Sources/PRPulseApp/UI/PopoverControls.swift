import SwiftUI

struct PopoverMoreMenu: View {
    @ObservedObject var viewModel: DashboardViewModel
    var actions: DashboardHostActions

    var body: some View {
        Menu {
            Menu("Layout") {
                ForEach(PopoverLayout.allCases) { layout in
                    Button {
                        Task { await viewModel.changePopoverLayout(to: layout) }
                    } label: {
                        if viewModel.settings.popoverLayout == layout { Label(layout.title, systemImage: "checkmark") }
                        else { Text(layout.title) }
                    }
                    .disabled(!viewModel.isReady || viewModel.isChangingLayout)
                }
            }
            Divider()
            Button("Settings…") {
                // Present after the native menu finishes tracking its selection.
                DispatchQueue.main.async { actions.showSettings() }
            }
                .accessibilityIdentifier("prpulse.settings")
                .keyboardShortcut(",")
            Button("Quit MergeOwl", action: actions.quit)
                .accessibilityIdentifier("prpulse.quit")
                .keyboardShortcut("q")
        } label: { Image(systemName: "ellipsis") }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(6)
        .accessibilityLabel("More")
        .accessibilityIdentifier("prpulse.more")
        .help("Layout, Settings, and Quit")
    }
}

struct CompactPRViewPicker: View {
    @ObservedObject var viewModel: DashboardViewModel

    private var selectedTitle: String {
        viewModel.savedViews.first { $0.id == viewModel.selectedSavedViewID }?.name ?? viewModel.selectedTab.rawValue
    }

    var body: some View {
        Menu {
            if !viewModel.savedViews.filter(\.enabled).isEmpty {
                Section("Saved views") {
                    ForEach(viewModel.savedViews.filter(\.enabled)) { view in
                        Button(view.name) { viewModel.selectSavedView(id: view.id) }
                            .accessibilityIdentifier("prpulse.saved-view.\(view.name)")
                    }
                }
            }
            Section("PR lists") {
                ForEach(PullRequestTab.allCases) { tab in
                    Button(tab.rawValue) { viewModel.selectDefaultTab(tab) }
                }
            }
        } label: {
            Label(selectedTitle, systemImage: "list.bullet")
                .lineLimit(1)
                .font(.headline)
        }
        .help("Choose a PR list or saved view. Current view: \(selectedTitle)")
        .accessibilityLabel("View: \(selectedTitle)")
        .accessibilityIdentifier("prpulse.view-picker")
    }
}

struct PRFilterMenu: View {
    @ObservedObject var viewModel: DashboardViewModel
    private var count: Int {
        [viewModel.filterState.hideReviewed, viewModel.filterState.hideSnoozed, viewModel.filterState.hideNotApplicable].filter { $0 }.count
    }

    var body: some View {
        Menu {
            Toggle("Hide reviewed", isOn: $viewModel.filterState.hideReviewed)
            Toggle("Hide snoozed", isOn: $viewModel.filterState.hideSnoozed)
            Toggle("Hide N/A", isOn: $viewModel.filterState.hideNotApplicable)
            Divider()
            Button("Reset filters") {
                viewModel.filterState.hideReviewed = false
                viewModel.filterState.hideSnoozed = false
                viewModel.filterState.hideNotApplicable = false
                viewModel.filterState.actionableOnly = false
            }
        } label: {
            Label(count == 0 ? "Filters" : "Filters \(count)", systemImage: "line.3.horizontal.decrease")
                .labelStyle(.titleAndIcon)
        }
        .fixedSize()
        .accessibilityLabel("Filters, \(count) active")
        .accessibilityIdentifier("prpulse.filters")
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Popover layout").font(.headline)
                Text("This preference applies to all accounts and is saved automatically.")
                    .foregroundStyle(.secondary)
                ForEach(PopoverLayout.allCases) { layout in
                    Button {
                        Task { await viewModel.changePopoverLayout(to: layout) }
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: viewModel.settings.popoverLayout == layout ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(viewModel.settings.popoverLayout == layout ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(layout == .tabbed ? "Tabbed — Default" : "Compact").font(.headline)
                                Text(layout.summary).foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    if layout == .tabbed {
                                        previewLabel("My PRs")
                                        previewLabel("Reviews", selected: true)
                                        previewLabel("Watched")
                                    } else { previewLabel("Review Requested ▾", selected: true) }
                                }
                                if layout == .tabbed { HStack { previewLabel("API work"); previewLabel("Saved views…") } }
                                RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.1)).frame(height: 22)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(viewModel.settings.popoverLayout == layout ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(layout.title)
                    .accessibilityAddTraits(viewModel.settings.popoverLayout == layout ? [.isSelected] : [])
                    .accessibilityIdentifier("prpulse.appearance.\(layout.rawValue)")
                    .disabled(!viewModel.isReady || viewModel.isChangingLayout)
                }
                Text("Current layout: \(viewModel.settings.popoverLayout.title)").font(.callout)
            }.padding(24)
        }
    }

    private func previewLabel(_ title: String, selected: Bool = false) -> some View {
        Text(title).font(.caption).padding(6)
            .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }
}
