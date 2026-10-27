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
        var coverageWarnings: [String] = []
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
    @Published private(set) var savedViews: [SavedPRView] = []
    @Published private(set) var selectedSavedViewID: UUID?
    private let savedViewStore: SavedPRViewStore
    private let restoreSavedSelection: Bool
    private var savingViews = false
    @Published private(set) var listStates: [PullRequestTab: PullRequestListState]
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var isReady = false
    private var lastPopoverRefreshAttempt: Date?
    var isCurrentListRefreshing: Bool { isRefreshing || listStates[selectedTab]?.isLoading == true }
    @Published private(set) var badgeCount: Int = 0
    @Published private(set) var viewerLogin: String = ""
    @Published private(set) var digestSnapshot = DigestSnapshot(openedCount: 0, reviewedCount: 0, timeframeDescription: "N/A")
    @Published var errorMessage: String?
    @Published private(set) var connectionPresentation: DashboardConnectionPresentation = .checking
    @Published private(set) var connectionErrors: [String] = []
    var accessWarnings: [String] {
        Array(Set(listStates.values.flatMap(\.warnings))).sorted()
    }
    var listCoverageWarnings: [String] {
        if selectedSavedViewID != nil { return Array(Set(listStates.values.flatMap(\.coverageWarnings))).sorted() }
        return listStates[selectedTab]?.coverageWarnings ?? []
    }
    private var publishingSavedLayout = false
    let ciMonitor: CIMonitor
    @Published var settings: AppSettings = .default {
        didSet {
            guard !publishingSavedLayout else { return }
            let snapshot = settings
            launch { [self] in
                guard !self.retired else { return }
                try await self.store.save(settings: snapshot)
                guard !self.retired else { return }
                if snapshot.ciFailureAlerts == settings.ciFailureAlerts && snapshot.ciRefreshInterval == settings.ciRefreshInterval && snapshot.quietHours == settings.quietHours {
                    self.ciMonitor.configure(snapshot)
                }
                await self.scheduler.start(interval: snapshot.refreshInterval) {
                    await self.refreshActiveTab()
                }
            }
        }
    }
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var isChangingLayout = false

    func changePopoverLayout(to layout: PopoverLayout) async {
        guard isReady, !retired, !isChangingLayout, settings.popoverLayout != layout else { return }
        isChangingLayout = true
        defer { isChangingLayout = false }
        do {
            try await store.savePopoverLayout(layout)
            guard !retired else { return }
            publishingSavedLayout = true
            settings.popoverLayout = layout
            publishingSavedLayout = false
        } catch {
            if !retired { errorMessage = "Could not save the layout. Please try again." }
        }
    }

    var currentRefreshIntervalMinutes: Int { Int(settings.refreshInterval / 60) }

    private let client: GitHubClient
    private let store: PullRequestStore
    private let notifier: NotificationDispatcher
    private let scheduler: RefreshScheduler
    private let digestComputer: DigestComputer
    private var hasBootstrapped = false
    private var retired = false
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var resetWaiters: [PullRequestTab: [CheckedContinuation<Void, Never>]] = [:]
    private var activeLoads: [PullRequestTab: UUID] = [:]
    private var latestOverrides: [String: PullRequestOverride] = [:]

    private func launch(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !retired else { return }
        let id = UUID()
        tasks[id] = Task { [weak self] in
            defer { self?.tasks.removeValue(forKey: id) }
            do { try await operation() }
            catch { if self?.retired == false { self?.errorMessage = "Could not save changes. Please try again." } }
        }
    }

    func retire() async {
        retired = true
        isReady = false
        store.lifetime.invalidate()
        let waiters = resetWaiters.values.flatMap { $0 }
        resetWaiters.removeAll()
        activeLoads.removeAll()
        waiters.forEach { $0.resume() }
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        ciMonitor.stop()
        await scheduler.stop()
        await notifier.retire()
        await store.retire()
        await savedViewStore.retire()
        listStates = Dictionary(uniqueKeysWithValues: PullRequestTab.allCases.map { ($0, PullRequestListState()) })
        viewerLogin = ""
        badgeCount = 0
        connectionErrors = []
        connectionPresentation = .checking
        filterState = FilterState()
        savedViews = []
        selectedSavedViewID = nil
        errorMessage = nil
        digestSnapshot = DigestSnapshot(openedCount: 0, reviewedCount: 0, timeframeDescription: "N/A")
        lastRefreshAt = nil
    }

    init(
        client: GitHubClient,
        store: PullRequestStore,
        notifier: NotificationDispatcher,
        scheduler: RefreshScheduler,
        digestComputer: DigestComputer,
        restoreSavedSelection: Bool = true
    ) {
        self.client = client
        self.store = store
        self.notifier = notifier
        self.scheduler = scheduler
        self.digestComputer = digestComputer
        self.ciMonitor = CIMonitor(client: client, directory: store.directory, lifetime: store.lifetime, notifier: notifier)
        self.savedViewStore = SavedPRViewStore(directory: store.directory, lifetime: store.lifetime)
        self.restoreSavedSelection = restoreSavedSelection
        self.listStates = Dictionary(uniqueKeysWithValues: PullRequestTab.allCases.map { ($0, PullRequestListState()) })
        ciMonitor.onChange = { [weak self] in
            guard let self, !retired else { return }
            for tab in PullRequestTab.allCases {
                guard var state = listStates[tab] else { continue }
                for index in state.rawItems.indices {
                    if let ci = ciMonitor.snapshots[state.rawItems[index].id],
                       ci.headSHA == state.rawItems[index].detail.ciHeadSHA,
                       ci.revision == state.rawItems[index].detail.ciRevision,
                       ci.checkedAt >= (state.rawItems[index].detail.ci?.checkedAt ?? .distantPast) {
                        state.rawItems[index].detail.ci = ci
                    }
                }
                listStates[tab] = state
            }
            recomputeDisplayedItems(); updateBadgeCount(); objectWillChange.send()
        }

        launch { [self] in
            guard !self.retired else { return }
            await bootstrap()
        }
    }

    func refreshActiveTab() async {
        guard !retired else { return }
        if selectedSavedViewID != nil { await refreshAllLoaded() }
        else { await loadPage(for: selectedTab, reset: true) }
    }

    func refreshForPopoverOpen(now: Date = Date()) async {
        guard isReady, !retired, !isCurrentListRefreshing else { return }
        if !currentItems.isEmpty, currentItems.allSatisfy({ item in
            guard let ci = item.pullRequest.detail.ci, ci.isComplete, !ci.isStale else { return false }
            return now.timeIntervalSince(ci.checkedAt) < 30
        }) { return }
        if let lastPopoverRefreshAttempt, now.timeIntervalSince(lastPopoverRefreshAttempt) < 30 { return }
        lastPopoverRefreshAttempt = now
        await refreshActiveTab()
    }

    func requestNotificationAuthorization() async {
        await notifier.requestAuthorizationIfNeeded()
    }

    func exportDiagnostics() async {
        // Create a simple diagnostic report
        var lines: [String] = []
        lines.append("MergeOwl Diagnostics")
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
        let filename = "MergeOwl-Diagnostics-\(Int(Date().timeIntervalSince1970)).txt"
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
        selectSavedView(id: nil)
        refreshIfNeeded(for: selectedTab)
    }

    func selectDefaultTab(_ tab: PullRequestTab) {
        selectedTab = tab
        selectedTabDidChange()
    }

    func moveViewSelection(forward: Bool) {
        let views = savedViews.filter(\.enabled)
        let current = selectedSavedViewID.flatMap { id in views.firstIndex { $0.id == id } }
        if let current {
            let next = current + (forward ? 1 : -1)
            if views.indices.contains(next) { selectSavedView(id: views[next].id) }
            else if next < 0 { selectDefaultTab(.watched) }
        } else if let index = PullRequestTab.allCases.firstIndex(of: selectedTab) {
            let next = index + (forward ? 1 : -1)
            if PullRequestTab.allCases.indices.contains(next) { selectDefaultTab(PullRequestTab.allCases[next]) }
            else if forward, let first = views.first { selectSavedView(id: first.id) }
        }
    }

    func filtersDidChange() {
        recomputeDisplayedItems()
        updateBadgeCount()
    }

    func presentationDidAppear() {
        recomputeDisplayedItems()
        updateBadgeCount()
    }

    func refreshAll() {
        launch { [self] in
            await refreshAllLoaded()
        }
    }

    func refreshAllLoaded() async {
        guard !retired, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for tab in PullRequestTab.allCases {
            guard !retired else { return }
            await loadPage(for: tab, reset: true)
        }
        guard !retired else { return }
        await updateDigest()
        lastRefreshAt = Date()
    }

    private var loadedItems: [PullRequestPresentation] {
        let calculator = PullRequestStatusCalculator(currentUserLogin: viewerLogin)
        var unique: [String: PullRequest] = [:]
        for tab in PullRequestTab.allCases {
            for pr in listStates[tab]?.rawItems ?? [] {
                if let old = unique[pr.id], old.updatedAt > pr.updatedAt { continue }
                unique[pr.id] = pr
            }
        }
        return unique.values.sorted { $0.updatedAt > $1.updatedAt || ($0.updatedAt == $1.updatedAt && $0.id < $1.id) }
            .map { PullRequestPresentation(pullRequest: $0, status: calculator.status(for: $0)) }
    }

    var currentItems: [PullRequestPresentation] {
        guard let view = savedViews.first(where: { $0.id == selectedSavedViewID && $0.enabled }) else {
            return listStates[selectedTab]?.displayedItems ?? []
        }
        return loadedItems.filter {
            SavedPRViewMatcher.matches($0, view: view, viewerLogin: viewerLogin) && passesFilters($0)
        }
    }

    var hasMoreCurrentItems: Bool {
        if selectedSavedViewID != nil { return listStates.values.contains { $0.hasNextPage } }
        return listStates[selectedTab]?.hasNextPage ?? false
    }

    func actionableCount(for view: SavedPRView) -> Int {
        loadedItems.filter { $0.status.isActionable && SavedPRViewMatcher.matches($0, view: view, viewerLogin: viewerLogin) }.count
    }

    func actionableCount(for tab: PullRequestTab) -> Int {
        let calculator = PullRequestStatusCalculator(currentUserLogin: viewerLogin)
        return Set((listStates[tab]?.rawItems ?? []).filter { calculator.status(for: $0).isActionable }.map(\.id)).count
    }

    func selectSavedView(id: UUID?) {
        let selected = id.flatMap { candidate in savedViews.contains { $0.id == candidate && $0.enabled } ? candidate : nil }
        selectedSavedViewID = selected
        launch { [self] in try await savedViewStore.select(selected) }
        if selected != nil { refreshAll() }
    }

    func saveView(_ view: SavedPRView) async throws {
        var next = savedViews
        if let index = next.firstIndex(where: { $0.id == view.id }) { next[index] = view }
        else { next.append(view) }
        try await replaceViews(next)
    }

    func deleteView(id: UUID) async throws { try await replaceViews(savedViews.filter { $0.id != id }) }

    func moveView(id: UUID, offset: Int) async throws {
        guard let index = savedViews.firstIndex(where: { $0.id == id }), savedViews.indices.contains(index + offset) else { return }
        var next = savedViews
        next.swapAt(index, index + offset)
        try await replaceViews(next)
    }

    private func replaceViews(_ values: [SavedPRView]) async throws {
        guard !retired, !savingViews else { throw CancellationError() }
        savingViews = true
        defer { savingViews = false }
        let next = try SavedPRView.validated(values)
        try await savedViewStore.save(next)
        guard !retired else { throw CancellationError() }
        savedViews = next
        if let id = selectedSavedViewID, !next.contains(where: { $0.id == id && $0.enabled }) {
            selectedTab = .reviewRequested
            selectSavedView(id: nil)
        }
    }

    private func passesFilters(_ pr: PullRequestPresentation) -> Bool {
        let item = pr.pullRequest
        return (filterState.searchText.isEmpty || item.title.localizedCaseInsensitiveContains(filterState.searchText) || item.repository.nameWithOwner.localizedCaseInsensitiveContains(filterState.searchText))
            && (!filterState.hideNotApplicable || item.override.state != .notApplicable)
            && (!filterState.hideSnoozed || !item.override.isSnoozed)
            && (!filterState.actionableOnly || pr.status.isActionable)
            && (!filterState.hideReviewed || pr.status.badge != .reviewed)
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
        launch { [self] in
            if selectedSavedViewID != nil {
                for tab in PullRequestTab.allCases where listStates[tab]?.hasNextPage == true { await loadPage(for: tab, reset: false) }
            } else { await loadPage(for: selectedTab, reset: false) }
        }
    }

    func perform(action: QuickAction, on pr: PullRequestPresentation) {
        launch { [self] in
            guard !self.retired else { return }
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

            guard !self.retired else { return }
            try await store.saveOverride(override, for: pr.pullRequest.id)
            guard !self.retired else { return }
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
        launch { [self] in await updateDigest() }
    }

    func testNotification() {
        launch { [self] in
            await notifier.requestAuthorizationIfNeeded()
            await notifier.sendTestNotification()
        }
    }

    // MARK: - Private

    private func bootstrap() async {
        if hasBootstrapped { return }
        hasBootstrapped = true

        do {
            let views = try await savedViewStore.load()
            let selected = await savedViewStore.selectedID()
            guard !retired else { return }
            savedViews = views
            selectedSavedViewID = restoreSavedSelection ? selected.flatMap { candidate in views.contains { $0.id == candidate && $0.enabled } ? candidate : nil } : nil
        } catch { errorMessage = "Saved views could not be loaded. The original file has been preserved." }

        let storedSettings = await store.loadSettings()
        guard !retired else { return }
        let warning = await store.storageWarning()
        guard !retired else { return }
        if let warning { errorMessage = warning }
        settings = storedSettings
        ciMonitor.configure(storedSettings)
        isReady = true

        do {
            let login = try await client.fetchViewer()
            guard !retired else { return }
            viewerLogin = login
            markConnected(as: viewerLogin)
        } catch {
            guard !retired else { return }
            if (error as? CancellationError) != nil {
                // Default without surfacing an error when cancelled
                viewerLogin = "me"
            } else {
                viewerLogin = "me"
                markConnectionError("Viewer lookup failed: \(error.localizedDescription)")
            }
        }

        recomputeDisplayedItems()
        updateBadgeCount()
        if settings.refreshOnLaunch {
            await refreshActiveTab()
        }

    }

    private func refreshIfNeeded(for tab: PullRequestTab) {
        let state = listStates[tab] ?? PullRequestListState()
        if state.rawItems.isEmpty {
            launch { [self] in
                await loadPage(for: tab, reset: true)
            }
        }
    }

    private func loadPage(for tab: PullRequestTab, reset: Bool) async {
        guard !retired else { return }
        var state = listStates[tab] ?? PullRequestListState()
        if state.isLoading {
            guard reset else { return }
            await withCheckedContinuation { resetWaiters[tab, default: []].append($0) }
            guard !retired else { return }
            await loadPage(for: tab, reset: true)
            return
        }
        state.isLoading = true
        listStates[tab] = state
        let requestID = UUID()
        activeLoads[tab] = requestID
        defer { finishLoad(for: tab, requestID: requestID) }

        let cursor = reset ? nil : state.cursor
        do {
            let page = try await client.fetchPullRequests(tab: tab, cursor: cursor)
            guard !retired else { return }
            var enriched: [PullRequest] = []
            for var item in page.items {
                if let incoming = item.detail.ci {
                    let previous = listStates.values.flatMap(\.rawItems).first(where: { $0.id == item.id })?.detail.ci
                    item.detail.ci = CIStatus.retainingPrevious(previous, incoming: incoming)
                }
                let override = await store.override(for: item.id)
                guard !retired else { return }
                item.override = override
                enriched.append(item)
            }

            await recordActivityEvents(from: enriched, tab: tab)
            guard !retired else { return }

            // A quick action may have changed loaded rows while the page was in flight.
            state = listStates[tab] ?? state
            enriched = enriched.map { item in
                var item = item
                if let override = latestOverrides[item.id] { item.override = override }
                return item
            }
            let combined = reset ? enriched : state.rawItems + enriched
            var order: [String] = []
            var unique: [String: PullRequest] = [:]
            for item in combined {
                if unique[item.id] == nil { order.append(item.id) }
                if let previous = unique[item.id], previous.updatedAt > item.updatedAt { continue }
                unique[item.id] = item
            }
            state.rawItems = order.compactMap { unique[$0] }

            state.cursor = page.cursor
            state.hasNextPage = page.hasNextPage
            state.warnings = reset ? page.warnings : Array(Set(state.warnings + page.warnings)).sorted()
            let coverage = page.coverageWarning.map { [$0] } ?? []
            state.coverageWarnings = reset ? coverage : Array(Set(state.coverageWarnings + coverage)).sorted()
            state.isLoading = false
            listStates[tab] = state
            finishLoad(for: tab, requestID: requestID)
            if !viewerLogin.isEmpty, viewerLogin != "me" {
                markConnected(as: viewerLogin)
            }
            recomputeDisplayedItems()
            updateBadgeCount()
            lastRefreshAt = Date()
            await updateDigest()
        } catch {
            guard !retired else { return }
            state = listStates[tab] ?? state
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

    private func finishLoad(for tab: PullRequestTab, requestID: UUID) {
        guard activeLoads[tab] == requestID else { return }
        activeLoads.removeValue(forKey: tab)
        let waiters = resetWaiters.removeValue(forKey: tab) ?? []
        waiters.forEach { $0.resume() }
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
        latestOverrides[prID] = override
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
        badgeCount = loadedItems.filter { $0.status.isActionable }.count
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
        guard !retired else { return }
        digestSnapshot = digestComputer.makeSnapshot(from: events, cadence: cadence)
    }

    private func recordActivityEvents(from pullRequests: [PullRequest], tab: PullRequestTab) async {
        let now = Date()
        let viewer = viewerLogin.lowercased()

        for pr in pullRequests {
            guard !retired else { return }
            if tab == .mine {
                let key = "activity-opened-\(pr.id)"
                if await store.ledgerTimestamp(for: key) == nil {
                    guard !retired else { return }
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
                guard !retired else { return }
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
