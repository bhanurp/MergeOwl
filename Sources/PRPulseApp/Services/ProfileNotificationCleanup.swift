import Foundation
import UserNotifications

protocol ProfileNotificationCenter: Sendable {
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func removePending(_ ids: [String]) async
    func removeDelivered(_ ids: [String]) async
}

enum ProfileNotificationCleanup {
    static func remove(profileID: UUID, center: any ProfileNotificationCenter = SystemProfileNotificationCenter()) async {
        let prefix = profileID.uuidString + "-"
        let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(prefix) }
        let delivered = await center.deliveredIdentifiers().filter { $0.hasPrefix(prefix) }
        await center.removePending(pending)
        await center.removeDelivered(delivered)
    }
}

private actor SystemProfileNotificationCenter: ProfileNotificationCenter {
    private var supported: Bool {
        #if E2E_TESTING
        return false
        #else
        return Bundle.main.bundleURL.pathExtension == "app"
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        #endif
    }
    func pendingIdentifiers() async -> [String] {
        guard supported else { return [] }
        return await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }
    func deliveredIdentifiers() async -> [String] {
        guard supported else { return [] }
        return await UNUserNotificationCenter.current().deliveredNotifications().map { $0.request.identifier }
    }
    func removePending(_ ids: [String]) async {
        guard supported else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
    func removeDelivered(_ ids: [String]) async {
        guard supported else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }
}
