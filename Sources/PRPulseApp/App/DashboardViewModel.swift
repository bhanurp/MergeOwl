import Foundation
import SwiftUI
import AppKit

@MainActor
final class DashboardViewModel: ObservableObject {
    struct PullRequestListState {
        var rawItems: [PullRequest] = []
        var displayedItems: [PullRequestPresentation] = []
        var cursor: String?
        var hasNextPage: Bool = false
        var isLoading: Bool = false
        var warnings: [String] = []
    }

    enum QuickAction {
        case markTodo
        case markNotApplicable
        case clearOverride
        case snoozeTomorrow
        case snooze(Date)
    }

    @Published var selectedTab: PullRequestTab = .reviewRequested
    @Published var filterState = FilterState()
    @Published private(set) var listStates: [PullRequestTab: PullRequestListState]
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var badgeCount: Int = 0
    @Published private(set) var viewerLogin: String = ""
    @Published private(set) var digestSnapshot = DigestSnapshot(openedCount: 0, reviewedCount: 0, timeframeDescription: "N/A")
    @Published var errorMessage: String?
    @Published private(set) var connectionPresentation: DashboardConnectionPresentation = .checking
    @Published private(set) var connectionErrors: [String] = []
    var accessWarnings: [String] {
        Array(Set(listStates.values.flatMap(\.warnings))).sorted()
    }
    @Published var settings: AppSettings = .default {
        didSet {
            Task {
                try await store.save(settings: settings)
                await scheduler.start(interval: settings.refreshInterval) {
                    await self.refreshActiveTab()
                }
            }
        }
    }
    @Published private(set) var lastRefreshAt: Date?

    var currentRefreshIntervalMinutes: Int { Int(settings.refreshInterval / 60) }

    private let client: GitHubClient
    private let store: PullRequestStore
    private let notifier: NotificationDispatcher
    private let scheduler: RefreshScheduler
    private let digestComputer: DigestComputer
    private var hasBootstrapped = false

    init(
        client: GitHubClient,
        store: PullRequestStore,
        notifier: NotificationDispatcher,
        scheduler: RefreshScheduler,
        digestComputer: DigestComputer
    ) {
        self.client = client
        self.store = store
        self.notifier = notifier
        self.scheduler = scheduler
        self.digestComputer = digestComputer
        self.listStates = Dictionary(uniqueKeysWithValues: PullRequestTab.allCases.map { ($0, PullRequestListState()) })

        Task {
            await bootstrap()
        }
    }

    func refreshActiveTab() async {
        await loadPage(for: selectedTab, reset: true)
    }

    func requestNotificationAuthorization() async {
        await notifier.requestAuthorizationIfNeeded()
    }

    func openSettingsJSON() async {
        // Determine the same directory used by PullRequestStore
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PRPulseApp", isDirectory: true)
        let settingsURL = directory.appendingPathComponent("settings.json")

        // Ensure directory exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // Ensure file exists with current settings if missing
        if !fm.fileExists(atPath: settingsURL.path) {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(settings)
                try data.write(to: settingsURL, options: .atomic)
            } catch {
                self.errorMessage = "Failed to create settings.json: \(error.localizedDescription)"
            }
        }

        // Open in the default editor
        NSWorkspace.shared.activateFileViewerSelecting([settingsURL])
        _ = NSWorkspace.shared.open(settingsURL)
    }

    func exportDiagnostics() async {
        // Create a simple diagnostic report
        var lines: [String] = []
        lines.append("PR Pulse Diagnostics")
        lines.append("Generated: \(Date().formatted(date: .abbreviated, time: .standard))")
        lines.append("")
        lines.append("Viewer: \(viewerLogin.isEmpty ? "(unknown)" : viewerLogin)")
        lines.append("Selected Tab: \(selectedTab.rawValue)")
        lines.append("Refresh On Launch: \(settings.refreshOnLaunch)")
        lines.append("Refresh Interval (min): \(Int(settings.refreshInterval / 60))")
        lines.append("Needs Re-Review Notifications: \(settings.notifyNeedsReview)")
        lines.append("Review Requested Notifications: \(settings.notifyNewReviewRequests)")
        lines.append("Digest Cadence: \(settings.digestCadence.rawValue)")
        lines.append("Default Snooze Hour: \(settings.snoozeDefaultHour)")
        lines.append("Watched Repositories: \(settings.watchedRepositories.map{ $0.nameWithOwner }.joined(separator: ", "))")
        if let last = lastRefreshAt {
            lines.append("Last Refresh: \(last.formatted(date: .abbreviated, time: .standard))")
        } else {
            lines.append("Last Refresh: Never")
        }

        let report = lines.joined(separator: "\n")

        // Write to a file on Desktop
        let fm = FileManager.default
        let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let filename = "PRPulse-Diagnostics-\(Int(Date().timeIntervalSince1970)).txt"
        let url = desktop.appendingPathComponent(filename)
        do {
            try report.data(using: .utf8)?.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            _ = NSWorkspace.shared.open(url)
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to export diagnostics: \(error.localizedDescription)"
            }
        }
    }

    func selectedTabDidChange() {
        refreshIfNeeded(for: selectedTab)
    }

    func filtersDidChange() {
        recomputeDisplayedItems()
    }

    func refreshAll() {
        Task {
            guard !isRefreshing else { return }
            isRefreshing = true
            defer { isRefreshing = false }

            for tab in PullRequestTab.allCases {
                await loadPage(for: tab, reset: true)
            }
            await updateDigest()
            lastRefreshAt = Date()
        }
    }

    func refreshNow() {
        refreshAll()
    }

    func accountConnectionDidSucceed(login: String) {
        viewerLogin = login
        markConnected(as: login)
        refreshAll()
    }

    func loadMoreCurrentTab() {
        Task {
            await loadPage(for: selectedTab, reset: false)
        }
    }

    func perform(action: QuickAction, on pr: PullRequestPresentation) {
        Task {
            var override = pr.pullRequest.override
            switch action {
            case .markTodo:
                override.state = .todo
                override.snoozedUntil = nil
            case .markNotApplicable:
                override.state = .notApplicable
            case .clearOverride:
                override = PullRequestOverride()
            case .snoozeTomorrow:
                let defaultHour = settings.snoozeDefaultHour
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(86_400))
                components.hour = defaultHour
                let target = Calendar.current.date(from: components) ?? Date().addingTimeInterval(86_400)
                override.snoozedUntil = target
                override.state = .todo
                await notifier.scheduleSnoozeReminder(for: pr.pullRequest, until: target)
            case .snooze(let date):
                override.state = .todo
                override.snoozedUntil = date
                await notifier.scheduleSnoozeReminder(for: pr.pullRequest, until: date)
            }

            try await store.saveOverride(override, for: pr.pullRequest.id)
            updateOverride(override, for: pr.pullRequest.id)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func clearConnectionErrors() {
        connectionErrors.removeAll()
    }

    func forceDigestRecompute() {
        Task { await updateDigest() }
    }

    func testNotification() {
        Task { @MainActor in
            await notifier.requestAuthorizationIfNeeded()
            await notifier.sendTestNotification()
        }
    }

    // MARK: - Private

    private func bootstrap() async {
        if hasBootstrapped { return }
        hasBootstrapped = true

        do {
            viewerLogin = try await client.fetchViewer()
            markConnected(as: viewerLogin)
        } catch {
            if (error as? CancellationError) != nil {
                // Default without surfacing an error when cancelled
                viewerLogin = "me"
            } else {
                viewerLogin = "me"
                markConnectionError("Viewer lookup failed: \(error.localizedDescription)")
            }
        }

        let storedSettings = await store.loadSettings()
        settings = storedSettings

        if settings.refreshOnLaunch {
            await refreshActiveTab()
        }

        await scheduler.start(interval: settings.refreshInterval) {
            await self.refreshActiveTab()
        }
    }

    private func refreshIfNeeded(for tab: PullRequestTab) {
        let state = listStates[tab] ?? PullRequestListState()
        if state.rawItems.isEmpty {
            Task {
                await loadPage(for: tab, reset: true)
            }
        }
    }

    private func loadPage(for tab: PullRequestTab, reset: Bool) async {
        var state = listStates[tab] ?? PullRequestListState()
        if state.isLoading { return }
        state.isLoading = true
        listStates[tab] = state

        let cursor = reset ? nil : state.cursor
        do {
            let page = try await client.fetchPullRequests(tab: tab, cursor: cursor)
            var enriched: [PullRequest] = []
            for var item in page.items {
                let override = await store.override(for: item.id)
                item.override = override
                enriched.append(item)
            }

            await recordActivityEvents(from: enriched, tab: tab)

            if reset {
                state.rawItems = enriched
            } else {
                state.rawItems.append(contentsOf: enriched)
            }

            state.cursor = page.cursor
            state.hasNextPage = page.hasNextPage
            state.warnings = reset ? page.warnings : Array(Set(state.warnings + page.warnings)).sorted()
            state.isLoading = false
            listStates[tab] = state
            if !viewerLogin.isEmpty, viewerLogin != "me" {
                markConnected(as: viewerLogin)
            }
            recomputeDisplayedItems()
            updateBadgeCount()
            lastRefreshAt = Date()
            await updateDigest()
        } catch {
            state.isLoading = false
            listStates[tab] = state
            // Ignore benign cancellations (e.g., overlapping refreshes)
            if (error as? CancellationError) != nil {
                return
            }
            if let githubError = error as? GitHubClientError, githubError.isAccessRestriction {
                state.warnings = [githubError.localizedDescription]
                listStates[tab] = state
                return
            }
            markConnectionError(error.localizedDescription)
        }
    }

    private func recomputeDisplayedItems() {
        guard !viewerLogin.isEmpty else { return }
        let calculator = PullRequestStatusCalculator(currentUserLogin: viewerLogin)
        for tab in PullRequestTab.allCases {
            guard var state = listStates[tab] else { continue }
            let filtered = state.rawItems.filter { pr in
                guard filterState.searchText.isEmpty || pr.title.localizedCaseInsensitiveContains(filterState.searchText) ||
                        pr.repository.nameWithOwner.localizedCaseInsensitiveContains(filterState.searchText) else {
                    return false
                }

                if filterState.hideNotApplicable, pr.override.state == .notApplicable {
                    return false
                }

                if filterState.hideSnoozed, pr.override.isSnoozed {
                    return false
                }

                return true
            }.compactMap { pr -> PullRequestPresentation? in
                let status = calculator.status(for: pr)
                if filterState.actionableOnly && !status.isActionable {
                    return nil
                }
                if filterState.hideReviewed && status.badge == .reviewed {
                    return nil
                }
                return PullRequestPresentation(pullRequest: pr, status: status)
            }

            state.displayedItems = filtered
            listStates[tab] = state
        }
    }

    private func updateOverride(_ override: PullRequestOverride, for prID: String) {
        for tab in PullRequestTab.allCases {
            guard var state = listStates[tab] else { continue }
            guard let index = state.rawItems.firstIndex(where: { $0.id == prID }) else { continue }
            state.rawItems[index].override = override
            listStates[tab] = state
        }
        recomputeDisplayedItems()
        updateBadgeCount()
    }

    private func updateBadgeCount() {
        let actionable = PullRequestTab.allCases.flatMap { tab -> [PullRequestPresentation] in
            (listStates[tab]?.displayedItems ?? [])
        }.filter { $0.status.isActionable }
        badgeCount = actionable.count
    }

    private func updateDigest() async {
        let cadence = settings.digestCadence
        guard cadence != .off else {
            digestSnapshot = DigestSnapshot(openedCount: 0, reviewedCount: 0, timeframeDescription: "Off")
            return
        }

        let now = Date()
        let days = cadence == .weekly ? 7 : 14
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let events = await store.recentActivity(since: cutoff)
        digestSnapshot = digestComputer.makeSnapshot(from: events, cadence: cadence)
    }

    private func recordActivityEvents(from pullRequests: [PullRequest], tab: PullRequestTab) async {
        let now = Date()
        let viewer = viewerLogin.lowercased()

        for pr in pullRequests {
            if tab == .mine {
                let key = "activity-opened-\(pr.id)"
                if await store.ledgerTimestamp(for: key) == nil {
                    do {
                        try await store.appendActivity(ActivityEvent(type: .openedMyPR, date: now))
                        try await store.updateLedger(date: now, for: key)
                    } catch {
                        // Activity logging should not break refresh behavior.
                    }
                }
            }

            guard !viewer.isEmpty, viewer != "me" else { continue }
            guard let latestMyReviewAt = latestReviewDateByCurrentUser(in: pr) else { continue }

            let stamp = Int(latestMyReviewAt.timeIntervalSince1970)
            let key = "activity-reviewed-observed-\(pr.id)-\(stamp)"
            if await store.ledgerTimestamp(for: key) == nil {
                do {
                    try await store.appendActivity(ActivityEvent(type: .reviewedPR, date: now))
                    try await store.updateLedger(date: now, for: key)
                } catch {
                    // Activity logging should not break refresh behavior.
                }
            }
        }
    }

    private func latestReviewDateByCurrentUser(in pullRequest: PullRequest) -> Date? {
        let viewer = viewerLogin.lowercased()
        return pullRequest.detail.reviews
            .filter { review in
                guard review.reviewer.lowercased() == viewer else { return false }
                switch review.state {
                case .approved, .changesRequested, .commented:
                    return true
                case .dismissed:
                    return false
                }
            }
            .map(\.submittedAt)
            .max()
    }

    private func markConnected(as viewerLogin: String) {
        connectionPresentation = .connected(viewerLogin: viewerLogin)
        connectionErrors.removeAll()
    }

    private func markConnectionError(_: String) {
        let entry = "\(Date().formatted(date: .omitted, time: .standard)): GitHub connection failed"
        if connectionErrors.last != entry {
            connectionErrors.append(entry)
        }
        connectionPresentation = .failed
    }
}
