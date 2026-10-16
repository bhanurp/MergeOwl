import Foundation
import UserNotifications

actor NotificationDispatcher {
    private let store: PullRequestStore
    private var retired = false
    private let namespace: String

    init(store: PullRequestStore, namespace: String = "legacy") {
        self.store = store
        self.namespace = namespace
    }

    func retire() { retired = true }

    private func notificationsSupported() -> Bool {
        guard !retired, store.lifetime.isActive else { return false }
        #if E2E_TESTING
        return false
        #else
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return false
        }
        #endif
        // Don't attempt in unit tests or non-app hosts
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil {
            return false
        }
        // Ensure we're running as a proper app bundle
        if Bundle.main.bundleURL.pathExtension != "app" {
            return false
        }
        return true
        #endif
    }

    func requestAuthorizationIfNeeded() async {
        guard notificationsSupported() else { return }
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                configureCategories(center: center)
            }
        } catch {
            NSLog("Notification permission error: \(error.localizedDescription)")
        }
    }

    func sendNeedsReviewNotification(for pullRequest: PullRequest) async {
        guard notificationsSupported() else { return }
        let center = UNUserNotificationCenter.current()

        let key = "\(pullRequest.id)-needs-review"
        let now = Date()
        if let last = await store.ledgerTimestamp(for: key), now.timeIntervalSince(last) < 86_400 {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Needs review"
        content.subtitle = pullRequest.title
        content.body = pullRequest.repository.nameWithOwner
        content.categoryIdentifier = "pr_actions"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            guard store.lifetime.isActive else {
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
                return
            }
            try await store.updateLedger(date: now, for: key)
        } catch {
            NSLog("Failed to send notification: \(error.localizedDescription)")
        }
    }

    func scheduleSnoozeReminder(for pullRequest: PullRequest, until date: Date) async {
        guard notificationsSupported() else { return }
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Snoozed PR ready"
        content.subtitle = pullRequest.title
        content.body = "Snooze expired"
        content.categoryIdentifier = "pr_actions"

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(namespace)-\(pullRequest.id)-snooze",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            if !store.lifetime.isActive { center.removePendingNotificationRequests(withIdentifiers: [request.identifier]) }
        } catch {
            NSLog("Failed to schedule snooze reminder: \(error.localizedDescription)")
        }
    }

    func sendTestNotification() async {
        guard notificationsSupported() else { return }
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "PR Pulse Test Notification"
        content.body = "Notifications are working."
        content.categoryIdentifier = "pr_actions"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(
            identifier: "prpulse-test-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            NSLog("Failed to schedule test notification: \(error.localizedDescription)")
        }
    }

    private func configureCategories(center: UNUserNotificationCenter) {
        let openAction = UNNotificationAction(
            identifier: "open",
            title: "Open",
            options: [.foreground]
        )
        let todoAction = UNNotificationAction(
            identifier: "todo",
            title: "Mark TODO",
            options: []
        )
        let ignoreAction = UNNotificationAction(
            identifier: "ignore",
            title: "Mark N/A",
            options: [.destructive]
        )
        let snoozeAction = UNNotificationAction(
            identifier: "snooze",
            title: "Snooze",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: "pr_actions",
            actions: [openAction, todoAction, snoozeAction, ignoreAction],
            intentIdentifiers: []
        )

        center.setNotificationCategories([category])
    }
}
