import SwiftUI
import AppKit

@available(macOS 14.0, *)
struct ContentView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var hostActions: DashboardHostActions = .noop
    var accounts: AccountSessionCoordinator? = nil
    @State private var showDigest = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            header
            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            if !viewModel.accessWarnings.isEmpty {
                Label("Some PR data is unavailable. Showing accessible PRs.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(viewModel.accessWarnings.joined(separator: "\n"))
                Link("Manage GitHub token access", destination: URL(string: "https://github.com/settings/tokens")!)
                    .font(.caption)
            }
            listContent
            footer
        }
        .padding()
        .sheet(isPresented: $showDigest) {
            DigestView(snapshot: viewModel.digestSnapshot)
                .frame(width: 360, height: 240)
                .overlay(alignment: .topTrailing) {
                    Button {
                        showDigest = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Close")
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .onExitCommand {
                    showDigest = false
                }
        }
        .onAppear {
            viewModel.presentationDidAppear()
            if viewModel.isReady && viewModel.settings.refreshOnLaunch {
                viewModel.refreshAll()
            }
        }
        .onChange(of: viewModel.isReady) {
            if viewModel.isReady && viewModel.settings.refreshOnLaunch { viewModel.refreshAll() }
        }
        .onChange(of: viewModel.selectedTab) { _ in
            Task { @MainActor in
                viewModel.selectedTabDidChange()
            }
        }
        .onChange(of: viewModel.filterState.searchText) { _ in
            Task { @MainActor in
                viewModel.filtersDidChange()
            }
        }
        .onChange(of: viewModel.filterState.actionableOnly) { _ in
            Task { @MainActor in
                viewModel.filtersDidChange()
            }
        }
        .onChange(of: viewModel.filterState.hideReviewed) { _ in
            Task { @MainActor in
                viewModel.filtersDidChange()
            }
        }
        .onChange(of: viewModel.filterState.hideSnoozed) { _ in
            Task { @MainActor in
                viewModel.filtersDidChange()
            }
        }
        .onChange(of: viewModel.filterState.hideNotApplicable) { _ in
            Task { @MainActor in
                viewModel.filtersDidChange()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let accounts {
                    AccountSelectorView(accounts: accounts, showSettings: hostActions.showSettings)
                        .disabled(viewModel.isChangingLayout)
                } else { Text("PR Pulse").font(.headline); Spacer() }
                Button { viewModel.refreshAll() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh now").accessibilityLabel("Refresh")
                    .accessibilityIdentifier("prpulse.refresh").keyboardShortcut("r")
                    .disabled(viewModel.isRefreshing)
                PopoverMoreMenu(viewModel: viewModel, actions: hostActions)
            }
            if viewModel.settings.popoverLayout == .tabbed {
                DefaultPRTabs(viewModel: viewModel)
                    .onMoveCommand { direction in
                        if direction == .left || direction == .right { viewModel.moveViewSelection(forward: direction == .right) }
                    }
                if viewModel.savedViews.contains(where: \.enabled) {
                    HStack(spacing: 6) {
                        Text("Saved views").font(.caption).foregroundStyle(.secondary)
                        PRViewTabStrip(viewModel: viewModel)
                    }
                }
            } else {
                HStack {
                    CompactPRViewPicker(viewModel: viewModel)
                    Spacer(minLength: 8)
                    actionableToggle
                }
            }
            HStack(spacing: 6) {
                searchField
                PRFilterMenu(viewModel: viewModel)
                if viewModel.settings.popoverLayout == .tabbed { actionableToggle }
            }
        }
    }
    private var searchField: some View {
            TextField("Search title or repo", text: Binding(
                get: { viewModel.filterState.searchText },
                set: { viewModel.filterState.searchText = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .background {
                HStack {
                    Button("") { searchFocused = true }.keyboardShortcut("f")
                    ForEach(Array(PullRequestTab.allCases.enumerated()), id: \.element) { index, tab in
                        Button("") { viewModel.selectDefaultTab(tab) }
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    }
                }.hidden()
            }
    }

    private var actionableToggle: some View {
        Toggle("Actionable", isOn: $viewModel.filterState.actionableOnly)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
            .fixedSize()
            .accessibilityIdentifier("prpulse.actionable")
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.currentItems) { presentation in
                    PullRequestRowView(
                        presentation: presentation,
                        actionHandler: { action in
                            viewModel.perform(action: action, on: presentation)
                        },
                        showAuthor: viewModel.selectedTab == .reviewRequested
                    )
                    Divider().padding(.vertical, 10)
                }

                if viewModel.hasMoreCurrentItems {
                    Button("Load more") {
                        viewModel.loadMoreCurrentTab()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                } else if viewModel.currentItems.isEmpty {
                    if let accounts, accounts.profiles.isEmpty, !accounts.isWorking, accounts.errorMessage == nil {
                        ContentUnavailableView {
                            Label("Connect GitHub", systemImage: "person.crop.circle")
                        } description: { Text("Add an account in Settings to start tracking your pull requests.") }
                        actions: { Button("Open account settings", action: hostActions.showSettings) }
                    } else { EmptyStateView().padding(.top, 40) }
                }
            }
            if viewModel.isRefreshing { ProgressView("Refreshing PRs…").controlSize(.small) }
            if viewModel.selectedSavedViewID != nil { Text("Showing loaded PRs • counts may grow as more pages load").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(viewModel.currentItems.count) shown · \(viewModel.currentItems.filter { $0.status.isActionable }.count) actionable")
                .font(.caption).foregroundStyle(.secondary)
                .help("Counts reflect the visible, loaded PRs. The menu-bar badge covers all loaded lists.")
            Spacer()
            connectionIndicator
            Button("Activity") {
                showDigest = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    private var connectionIndicator: some View {
        Group {
            if let accounts, accounts.profiles.isEmpty, !accounts.isWorking, accounts.errorMessage == nil {
                Button("Connect GitHub", action: hostActions.showSettings)
            } else if viewModel.connectionPresentation.isConnected {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(viewModel.lastRefreshAt.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Connected")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .help(viewModel.connectionPresentation.statusText)
                .accessibilityLabel(viewModel.connectionPresentation.statusText)
            } else if viewModel.connectionPresentation == .checking {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(viewModel.connectionPresentation.statusText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else {
                Button {
                    hostActions.showConnectionErrors()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(viewModel.connectionPresentation.statusText)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                .buttonStyle(.plain)
                .help("Show connection errors")
            }
        }
    }
}


private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.badge.xmark")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No pull requests")
                .font(.headline)
            Text("Adjust filters or refresh to fetch the latest data.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
