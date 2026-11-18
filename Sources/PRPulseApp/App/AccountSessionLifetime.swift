import Foundation

/// Shared by actor-bound stores/notifications so retirement takes effect before any await.
final class AccountSessionLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        active = false
    }
}
