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
            if let accounts { AccountSelectorView(accounts: accounts, showSettings: hostActions.showSettings) }
            header
            if viewModel.savedViews.contains(where: \.enabled) { PRViewTabStrip(viewModel: viewModel) }
            filters
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DefaultPRTabs(viewModel: viewModel)
                .onMoveCommand { direction in
                    if direction == .left || direction == .right { viewModel.moveViewSelection(forward: direction == .right) }
                }
            }
            HStack(spacing: 8) {
                searchField
                Button {
                    viewModel.refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh now")
                .accessibilityIdentifier("prpulse.refresh")
                .keyboardShortcut("r")

                Button {
                    hostActions.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .accessibilityIdentifier("prpulse.settings")
                .keyboardShortcut(",", modifiers: [.command])

                Button {
                    hostActions.quit()
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit PR Pulse")
                .accessibilityIdentifier("prpulse.quit")
                .keyboardShortcut("q", modifiers: [.command])
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

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                FilterToggle(title: "Actionable", systemImage: "bolt.badge.a", isOn: Binding(
                    get: { viewModel.filterState.actionableOnly },
                    set: { viewModel.filterState.actionableOnly = $0 }
                ))

                FilterToggle(title: "Hide reviewed", systemImage: "eye.slash", isOn: Binding(
                    get: { viewModel.filterState.hideReviewed },
                    set: { viewModel.filterState.hideReviewed = $0 }
                ))

                FilterToggle(title: "Hide snoozed", systemImage: "zzz", isOn: Binding(
                    get: { viewModel.filterState.hideSnoozed },
                    set: { viewModel.filterState.hideSnoozed = $0 }
                ))

                FilterToggle(title: "Hide N/A", systemImage: "nosign", isOn: Binding(
                    get: { viewModel.filterState.hideNotApplicable },
                    set: { viewModel.filterState.hideNotApplicable = $0 }
                ))
            }
        }
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.currentItems) { presentation in
                    PullRequestRowView(
                        presentation: presentation,
                        actionHandler: { action in
                            viewModel.perform(action: action, on: presentation)
                        },
                        showAuthor: viewModel.selectedTab == .reviewRequested
                    )
                }

                if viewModel.hasMoreCurrentItems {
                    Button("Load more") {
                        viewModel.loadMoreCurrentTab()
                    }
                    .buttonStyle(.borderedProminent)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Digest")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(viewModel.digestSnapshot.openedCount) opened • \(viewModel.digestSnapshot.reviewedCount) reviewed")
                    .font(.footnote)
            }
            Spacer()
            connectionIndicator
            Button("View digest") {
                showDigest = true
            }
            .buttonStyle(.bordered)
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
                    Text(viewModel.connectionPresentation.statusText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
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

private struct FilterToggle: View {
    var title: String
    var systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(title, systemImage: systemImage)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(isOn ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
