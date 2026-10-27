import Foundation

protocol CINotificationSending: Sendable {
    func requestAuthorizationIfNeeded() async
    func ciPermissionDescription() async -> String
    func sendCIFailure(for pr: PullRequest, checks: [CICheck]) async -> Bool
}

/// One monitor per account session. Never depends on the selected tab or visible filters.
@MainActor
final class CIMonitor {
    private let client: GitHubClient
    private let lifetime: AccountSessionLifetime
    private let notifier: any CINotificationSending
    private let directory: URL
    private var storage: CIMonitorStore?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var configured = false
    private var enabled = false
    private var interval: TimeInterval = 300
    private var quietHours: QuietHours?
    private var polling = false
    private var verificationOrder: [String: Int] = [:]
    private var verificationSequence = 0
    private(set) var snapshots: [String: CIStatus] = [:]
    private(set) var mutedIDs = Set<String>()
    private(set) var message = "Failure alerts off"
    private(set) var lastChecked: Date?
    private(set) var nextCheck: Date?
    private(set) var notificationPermission = ""
    var onChange: (() -> Void)?

    init(client: GitHubClient, directory: URL, lifetime: AccountSessionLifetime, notifier: any CINotificationSending) {
        self.client = client; self.directory = directory; self.lifetime = lifetime; self.notifier = notifier
    }
    func configure(_ settings: AppSettings) {
        guard lifetime.isActive else { return }
        let nextInterval = [60.0, 300, 900, 1800].contains(settings.ciRefreshInterval) ? settings.ciRefreshInterval : 300
        quietHours = settings.quietHours
        guard !configured || enabled != settings.ciFailureAlerts || interval != nextInterval else { return }
        let newlyEnabled = configured && !enabled && settings.ciFailureAlerts
        configured = true; enabled = settings.ciFailureAlerts; interval = nextInterval
        task?.cancel(); generation = UUID(); nextCheck = nil
        do {
            if storage == nil { storage = try CIMonitorStore(directory: directory, lifetime: lifetime) }
            if newlyEnabled { try storage?.resetBaselines() }
        } catch {
            message = "CI monitoring data could not be read or saved. Original data is preserved."
            onChange?(); return
        }
        guard enabled else { message = "Failure alerts off"; onChange?(); return }
        message = "Checking all accessible open My PRs…"
        let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            if newlyEnabled { await notifier.requestAuthorizationIfNeeded() }
            while !Task.isCancelled && lifetime.isActive && token == generation {
                // A replaced pass may still be unwinding an uncancellable request.
                while polling && !Task.isCancelled && lifetime.isActive && token == generation {
                    do { try await Task.sleep(for: .milliseconds(20)) }
                    catch { return }
                }
                guard !Task.isCancelled, lifetime.isActive, token == generation else { return }
                await poll()
                guard !Task.isCancelled, lifetime.isActive, token == generation else { return }
                let deadline = max(Date().addingTimeInterval(interval), nextCheck ?? .distantPast)
                nextCheck = deadline; onChange?()
                do { try await Task.sleep(for: .seconds(max(1, deadline.timeIntervalSinceNow))) }
                catch { return }
            }
        }
        onChange?()
    }
    func stop() { enabled = false; generation = UUID(); task?.cancel(); task = nil; nextCheck = nil }

    func setMuted(_ muted: Bool, for id: String) throws {
        guard lifetime.isActive else { throw CancellationError() }
        if storage == nil { storage = try CIMonitorStore(directory: directory, lifetime: lifetime) }
        try storage?.setMuted(muted, for: id)
        if muted { mutedIDs.insert(id) } else { mutedIDs.remove(id) }
        onChange?()
    }
    func isMuted(_ id: String) -> Bool {
        if let storage { return storage.isMuted(id) }
        return mutedIDs.contains(id)
    }

    func poll() async {
        guard enabled, !polling, lifetime.isActive, let storage else { return }
        polling = true
        defer { polling = false }
        let token = generation
        func active() -> Bool { lifetime.isActive && enabled && token == generation && !Task.isCancelled }
        do {
            let viewer = try await client.fetchViewer()
            guard active() else { return }
            var cursor: String?
            var cursors = Set<String>()
            var open: [String: PullRequest] = [:]
            var warnings: [String] = []
            repeat {
                let page = try await client.fetchPullRequests(tab: .mine, cursor: cursor)
                guard active() else { return }
                warnings += page.warnings
                if let coverage = page.coverageWarning { warnings.append(coverage) }
                for pr in page.items where pr.author.login.caseInsensitiveCompare(viewer) == .orderedSame { open[pr.id] = pr }
                if !page.hasNextPage { break }
                guard let next = page.cursor, cursors.insert(next).inserted else {
                    warnings.append("GitHub did not provide a usable page cursor."); break
                }
                cursor = next
            } while true
            let discoveryComplete = warnings.isEmpty
            let ordered = open.values.sorted {
                let lhs = verificationOrder[$0.id] ?? -1, rhs = verificationOrder[$1.id] ?? -1
                return lhs == rhs ? $0.id < $1.id : lhs < rhs
            }
            for pr in ordered {
                guard active() else { return }
                var snapshot: CIStatus = .unavailable
                do {
                    if let ci = pr.detail.ci { snapshot = ci }
                    else { snapshot = try await client.fetchCI(for: pr) }
                    guard active() else { return }
                    // Before a failure can notify, revalidate against the live PR revision.
                    if snapshot.checks.contains(where: { $0.state == .failure }) {
                        let verified = try await client.revalidateCI(for: pr)
                        guard active() else { return }
                        guard verified.headSHA == snapshot.headSHA, verified.revision == snapshot.revision else {
                            throw GitHubClientError.obsoleteCI
                        }
                        snapshot = verified
                        verificationSequence += 1
                        verificationOrder[pr.id] = verificationSequence
                    }
                } catch {
                    if error is CancellationError { throw error }
                    if case GitHubClientError.rateLimited = error { throw error }
                    snapshot = .unavailable
                    snapshot.warning = error.localizedDescription
                }
                snapshot = CIStatus.retainingPrevious(snapshots[pr.id], incoming: snapshot)
                if !snapshot.isComplete || snapshot.isStale { warnings.append("Some CI data is unavailable.") }
                snapshots[pr.id] = snapshot
                let quiet = Self.isQuiet(hour: Calendar.current.component(.hour, from: Date()), hours: quietHours)
                let failures = try storage.observe(pr: pr, snapshot: snapshot, deferReportable: !quiet)
                if storage.isMuted(pr.id) { mutedIDs.insert(pr.id) } else { mutedIDs.remove(pr.id) }
                if !failures.isEmpty && !quiet {
                    guard active() else { return }
                    let accepted = await notifier.sendCIFailure(for: pr, checks: failures)
                    guard active() else { return }
                    if accepted { _ = try storage.observe(pr: pr, snapshot: snapshot) }
                }
            }
            guard active() else { return }
            if discoveryComplete {
                try storage.retainOpen(Set(open.keys))
                snapshots = snapshots.filter { open[$0.key] != nil }
                verificationOrder = verificationOrder.filter { open[$0.key] != nil }
            }
            if warnings.isEmpty {
                message = "Monitoring \(open.count) open My PRs"
            } else { message = "Monitoring accessible My PRs; coverage is incomplete. \(Array(Set(warnings)).sorted().joined(separator: " "))" }
            lastChecked = Date()
            notificationPermission = await notifier.ciPermissionDescription()
            guard active() else { return }
            nextCheck = Date().addingTimeInterval(interval)
            onChange?()
        } catch {
            guard active() else { return }
            if case GitHubClientError.rateLimited(let until) = error { nextCheck = until }
            for id in Array(snapshots.keys) {
                snapshots[id]?.isStale = true
                snapshots[id]?.warning = "Could not refresh checks. These are the last successful results."
            }
            message = "CI monitoring paused: \(error.localizedDescription) Previous results may be stale."
            onChange?()
        }
    }
    nonisolated static func isQuiet(hour: Int, hours: QuietHours?) -> Bool {
        guard let hours else { return false }
        if hours.startHour == hours.endHour { return false }
        return hours.startHour < hours.endHour
            ? hour >= hours.startHour && hour < hours.endHour
            : hour >= hours.startHour || hour < hours.endHour
    }
}
