import Foundation

actor RefreshScheduler {
    private var task: Task<Void, Never>?

    func start(interval: TimeInterval, action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        guard interval > 0 else { return }

        task = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await action()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
