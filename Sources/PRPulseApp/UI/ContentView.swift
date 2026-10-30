import AppKit
import SwiftUI

@available(macOS 14.0, *)
struct ContentView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var hostActions: DashboardHostActions = .noop
    var accounts: AccountSessionCoordinator? = nil
    @State private var showDigest = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = viewModel.currentItems
        return VStack(spacing: 8) {
            header
            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            if !viewModel.accessWarnings.isEmpty {
                Label(
                    "Some PR data is unavailable. Showing accessible PRs.", systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .help(viewModel.accessWarnings.joined(separator: "\n"))
                Link("Manage GitHub token access", destination: URL(string: "https://github.com/settings/tokens")!)
                    .font(.caption)
            }
            listContent(items)
            ForEach(viewModel.listCoverageWarnings, id: \.self) { warning in
                Text(warning).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("prpulse.coverage-warning")
            }
            footer(items)
        }
        .font(.system(size: 13))
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let accounts {
                    AccountSelectorView(accounts: accounts, showSettings: hostActions.showSettings)
                        .disabled(viewModel.isChangingLayout)
                } else {
                    Text("MergeOwl").font(.headline)
                    Spacer()
                }
                actionableToggle
                Button {
                    viewModel.refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Refresh now").accessibilityLabel("Refresh")
                .accessibilityIdentifier("prpulse.refresh").keyboardShortcut("r")
                .disabled(viewModel.isRefreshing)
                PopoverMoreMenu(viewModel: viewModel, actions: hostActions)
            }
            if viewModel.settings.popoverLayout == .tabbed {
                DefaultPRTabs(viewModel: viewModel)
                    .onMoveCommand { direction in
                        if direction == .left || direction == .right {
                            viewModel.moveViewSelection(forward: direction == .right)
                        }
                    }
                if viewModel.savedViews.contains(where: \.enabled) {
                    PRViewTabStrip(viewModel: viewModel)
                }
                HStack(spacing: 8) {
                    searchField
                    PRFilterMenu(viewModel: viewModel)
                }
            } else {
                HStack(spacing: 8) {
                    CompactPRViewPicker(viewModel: viewModel)
                        .frame(width: 116, alignment: .leading)
                    searchField
                    PRFilterMenu(viewModel: viewModel)
                }
            }
        }
    }
    private var searchField: some View {
        TextField(
            "Search PRs or repos",
            text: Binding(
                get: { viewModel.filterState.searchText },
                set: { viewModel.filterState.searchText = $0 }
            )
        )
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel("Search title or repo")
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
        Button {
            viewModel.filterState.actionableOnly.toggle()
        } label: {
            Image(systemName: "bolt.badge.clock")
                .frame(width: 24, height: 24).contentShape(Rectangle())
                .foregroundStyle(viewModel.filterState.actionableOnly ? Color.accentColor : .secondary)
                .background(
                    viewModel.filterState.actionableOnly ? Color.accentColor.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Actionable")
        .accessibilityValue(viewModel.filterState.actionableOnly ? "On" : "Off")
        .accessibilityAddTraits(viewModel.filterState.actionableOnly ? [.isSelected] : [])
        .help("Show only actionable PRs")
        .accessibilityIdentifier("prpulse.actionable")
    }

    private func listContent(_ items: [PullRequestPresentation]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { presentation in
                    PullRequestRowView(
                        presentation: presentation,
                        actionHandler: { action in
                            viewModel.perform(action: action, on: presentation)
                        },
                        showAuthor: viewModel.selectedTab == .reviewRequested,
                        ciRefreshInterval: viewModel.settings.ciRefreshInterval,
                        ciRefreshing: viewModel.isCurrentListRefreshing,
                        ciMuted: viewModel.ciMonitor.isMuted(presentation.id),
                        toggleCIMute: presentation.pullRequest.author.login.caseInsensitiveCompare(
                            viewModel.viewerLogin) == .orderedSame
                            ? {
                                do {
                                    try viewModel.ciMonitor.setMuted(
                                        !viewModel.ciMonitor.isMuted(presentation.id), for: presentation.id)
                                } catch { viewModel.errorMessage = "Could not save CI mute. Please try again." }
                            } : nil
                    )
                    Divider().padding(.leading, 26)
                }

                if viewModel.hasMoreCurrentItems {
                    Button("Load more") {
                        viewModel.loadMoreCurrentTab()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                } else if items.isEmpty {
                    if let accounts, accounts.profiles.isEmpty, !accounts.isWorking, accounts.errorMessage == nil {
                        ContentUnavailableView {
                            Label("Connect GitHub", systemImage: "person.crop.circle")
                        } description: {
                            Text("Add an account in Settings to start tracking your pull requests.")
                        } actions: {
                            Button("Open account settings", action: hostActions.showSettings)
                        }
                    } else {
                        EmptyStateView().padding(.top, 40)
                    }
                }
            }
            if viewModel.isRefreshing { ProgressView("Refreshing PRs…").controlSize(.small) }
            if viewModel.selectedSavedViewID != nil {
                Text("Showing loaded PRs • counts may grow as more pages load").font(.caption).foregroundStyle(
                    .secondary)
            }
        }
        .accessibilityIdentifier("prpulse.pr-list")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func footer(_ items: [PullRequestPresentation]) -> some View {
        HStack(spacing: 8) {
            connectionIndicator
            Spacer(minLength: 4)
            Text("\(items.count) shown")
                .monospacedDigit().foregroundStyle(.secondary)
                .help(
                    "\(items.filter { $0.status.isActionable }.count) actionable in this view. Counts cover loaded PRs only; the menu-bar badge covers all loaded lists."
                )
            if let date = viewModel.lastRefreshAt {
                Text(date, format: .dateTime.hour().minute())
                    .monospacedDigit().foregroundStyle(.secondary)
                    .help("Last list refresh: \(date.formatted())")
            }
            Button("Activity") {
                showDigest = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .font(.system(size: 11))
        .lineLimit(1)
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
                    Text("Connected")
                        .font(.system(size: 11))
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
