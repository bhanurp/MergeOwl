// Isolated Sparkle integration host, never the installed MergeOwl app.
import AppKit
import Sparkle

@MainActor
final class UpgradeProbe: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private let passiveReminders = SparkleUpdateDriver()
    private var controller: SPUStandardUpdaterController?
    private var timeout: Timer?
    private func record(_ value: String) {
        guard let path = ProcessInfo.processInfo.environment["MERGEOWL_PROBE_LOG"] else { return }
        if let data = (value + "\n").data(using: .utf8) {
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            if let file = FileHandle(forWritingAtPath: path) { file.seekToEndOfFile(); file.write(data); try? file.close() }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        record("launch:\(version)")
        if ProcessInfo.processInfo.environment["MERGEOWL_PROBE_VERIFY"] == "1" {
            NSApp.terminate(nil)
            return
        }
        // Only this throwaway bundle's preferences are used. Production defaults
        // and production account/credential stores are never loaded.
        UserDefaults.standard.set("preserved-fixture", forKey: "upgradeContinuity")
        passiveReminders.onStateChange = { state in
            if case .available = state {
                self.record("attention-without-focus")
                NSApp.terminate(nil)
            }
        }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: passiveReminders)
        do {
            try controller!.updater.start()
            controller!.updater.automaticallyChecksForUpdates = false
            controller!.updater.automaticallyDownloadsUpdates = true
            record("preferences:checks=\(controller!.updater.automaticallyChecksForUpdates),downloads=\(controller!.updater.automaticallyDownloadsUpdates)")
            controller!.updater.checkForUpdatesInBackground()
        } catch {
            record("error:\((error as NSError).code)")
            NSApp.terminate(nil)
        }
        timeout = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { _ in
            Task { @MainActor in self.record("timeout"); NSApp.terminate(nil) }
        }
    }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        record("ready:\(item.versionString)")
        // Deliberate natural quit of this disposable host; never call the
        // immediate-install handler and never terminate another application.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        return true
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { record("found:\(item.versionString)") }
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) { record("download:\(item.versionString)") }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor check: SPUUpdateCheck, error: Error?) { record("cycle-finished") }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        record("error:\((error as NSError).code)")
        NSApp.terminate(nil)
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        record("no-update")
        NSApp.terminate(nil)
    }
    func applicationWillTerminate(_ notification: Notification) {
        timeout?.invalidate()
        record("continuity:\(UserDefaults.standard.string(forKey: "upgradeContinuity") ?? "missing")")
        record("quit")
    }
}

@main struct ProbeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = UpgradeProbe()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
