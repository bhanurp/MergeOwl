import XCTest
@testable import PRPulseApp

final class AccountNotificationRemovalTests: XCTestCase {
    func testCleanupRemovesOnlyTheRemovedProfilesPendingAndDeliveredRequests() async {
        let a = UUID(), b = UUID()
        let center = NotificationRemovalFixture(ids: ["\(a.uuidString)-pr-snooze", "\(a.uuidString)-review", "\(b.uuidString)-pr-snooze", "prpulse-test"])
        await ProfileNotificationCleanup.remove(profileID: a, center: center)
        let pending = await center.pending
        let delivered = await center.delivered
        XCTAssertEqual(pending, ["\(b.uuidString)-pr-snooze", "prpulse-test"])
        XCTAssertEqual(delivered, pending)
    }

    @MainActor
    func testRemovingInactiveAccountCleansItsNotificationsWithoutSwitching() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var removed: [UUID] = []
        let coordinator = AccountSessionCoordinator(directory: root, credentials: MemoryCredentials(),
            validate: { .init(id: $0, login: $0) }, makeClient: { _, _ in MockGitHubClient() },
            removeNotifications: { removed.append($0) })
        await coordinator.start()
        try await coordinator.connect(token: "alice", replacing: nil)
        try await coordinator.connect(token: "bob", replacing: nil)
        let active = coordinator.activeProfileID
        let bob = try XCTUnwrap(coordinator.profiles.first { $0.login == "bob" })
        try await coordinator.removeAccount(id: bob.id)
        XCTAssertEqual(removed, [bob.id])
        XCTAssertEqual(coordinator.activeProfileID, active)
        await coordinator.dashboard.retire()
    }
}

private actor NotificationRemovalFixture: ProfileNotificationCenter {
    var pending: [String]
    var delivered: [String]
    init(ids: [String]) { pending = ids; delivered = ids }
    func pendingIdentifiers() async -> [String] { pending }
    func deliveredIdentifiers() async -> [String] { delivered }
    func removePending(_ ids: [String]) async { pending.removeAll { ids.contains($0) } }
    func removeDelivered(_ ids: [String]) async { delivered.removeAll { ids.contains($0) } }
}
