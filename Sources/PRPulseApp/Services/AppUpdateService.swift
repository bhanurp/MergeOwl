import Foundation
import Combine

enum UpdateState: Equatable {
    case unconfigured(String)
    case idle
    case checking
    case downloading(progress: Double?)
    case ready(version: String)
    case upToDate
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading: true
        default: false
        }
    }
}

@MainActor
protocol UpdateDriver: AnyObject {
    var configurationError: String? { get }
    var canCheckForUpdates: Bool { get }
    var automaticUpdatesEnabled: Bool { get }
    var lastCheckAt: Date? { get }
    var onStateChange: ((UpdateState) -> Void)? { get set }
    func start() throws
    func checkForUpdates()
    func setAutomaticUpdatesEnabled(_ enabled: Bool)
    func installAndRelaunch()
}

@MainActor
final class AppUpdateService: ObservableObject {
    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var automaticUpdatesEnabled = false
    @Published private(set) var lastCheckAt: Date?
    @Published private(set) var canCheckForUpdates = false
    private let driver: any UpdateDriver
    private var started = false

    init(driver: any UpdateDriver) {
        self.driver = driver
        driver.onStateChange = { [weak self] state in
            guard let self else { return }
            self.state = state
            self.synchronize()
        }
        if let error = driver.configurationError { state = .unconfigured(error) }
        synchronize()
    }

    func start() {
        guard !started, driver.configurationError == nil else { return }
        do {
            try driver.start()
            started = true
        } catch {
            state = .failed(error.localizedDescription)
        }
        synchronize()
    }

    func checkForUpdates() {
        guard started, canCheckForUpdates else { return }
        state = .checking
        synchronize()
        driver.checkForUpdates()
    }

    func setAutomaticUpdatesEnabled(_ enabled: Bool) {
        guard driver.configurationError == nil else { return }
        driver.setAutomaticUpdatesEnabled(enabled)
        synchronize()
    }

    func installAndRelaunch() {
        guard started, case .ready = state else { return }
        driver.installAndRelaunch()
    }

    private func synchronize() {
        automaticUpdatesEnabled = driver.configurationError == nil && driver.automaticUpdatesEnabled
        lastCheckAt = driver.lastCheckAt
        canCheckForUpdates = started && driver.configurationError == nil && driver.canCheckForUpdates && !state.isBusy
    }
}
