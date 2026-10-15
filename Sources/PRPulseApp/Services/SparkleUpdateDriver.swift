import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

enum UpdateConfiguration {
    static func validationError(info: [String: Any]) -> String? {
        guard info["PRPulseUpdatesEnabled"] as? Bool == true else {
            return "Automatic updates are not configured for this build. Install releases manually from GitHub."
        }
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            return "A secure update feed has not been configured."
        }
        guard let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true else {
            return "Update signature verification has not been configured."
        }
        return nil
    }
}

#if canImport(Sparkle)
@MainActor
final class SparkleUpdateDriver: NSObject, UpdateDriver, SPUUpdaterDelegate {
    let configurationError: String?
    var onStateChange: ((UpdateState) -> Void)?
    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []
    private var state: UpdateState = .idle
    private var installHandler: (() -> Void)?

    override init() {
        configurationError = UpdateConfiguration.validationError(info: Bundle.main.infoDictionary ?? [:])
        super.init()
        // Do not even instantiate Sparkle until the embedded trust configuration is valid.
        guard configurationError == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }
    var automaticUpdatesEnabled: Bool {
        guard let updater = controller?.updater else { return false }
        // Scheduled checks are the canonical opt-in. A mixed Sparkle preference
        // must not make the UI claim checks are disabled while they still run.
        return updater.automaticallyChecksForUpdates
    }
    var lastCheckAt: Date? { controller?.updater.lastUpdateCheckDate }

    func start() throws {
        guard let updater = controller?.updater else { return }
        try updater.start()
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.publishCurrentState() }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.publishCurrentState() }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.publishCurrentState() }
            }
        ]
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    func setAutomaticUpdatesEnabled(_ enabled: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = enabled
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func installAndRelaunch() { installHandler?() }

    private func publish(_ newState: UpdateState) {
        state = newState
        publishCurrentState()
    }

    private func publishCurrentState() { onStateChange?(state) }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        publish(.downloading(progress: nil))
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installHandler = immediateInstallHandler
        publish(.ready(version: item.displayVersionString))
        // Retain control over reminders; only an explicit UI action invokes the handler.
        // Sparkle still installs on natural termination.
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        if (error as NSError).domain == SUSparkleErrorDomain,
           (error as NSError).code == SUError.noUpdateError.rawValue { publish(.upToDate) }
        else { publish(.failed(error.localizedDescription)) }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error { self.updater(updater, didAbortWithError: error) }
        else if installHandler == nil { publish(.idle) }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) { publish(.upToDate) }
}
#endif

@MainActor
final class DisabledUpdateDriver: UpdateDriver {
    let configurationError: String? = "Updates are disabled in this development or test build."
    var canCheckForUpdates: Bool { false }
    var automaticUpdatesEnabled: Bool { false }
    var lastCheckAt: Date? { nil }
    var onStateChange: ((UpdateState) -> Void)?
    func start() throws {}
    func checkForUpdates() {}
    func setAutomaticUpdatesEnabled(_ enabled: Bool) {}
    func installAndRelaunch() {}
}
