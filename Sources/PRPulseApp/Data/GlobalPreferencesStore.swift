import Foundation

actor GlobalPreferencesStore {
    private let file: URL
    private let legacy: URL
    init(directory: URL) {
        file = directory.appendingPathComponent("preferences.json")
        legacy = directory.appendingPathComponent("settings.json")
    }
    func load() throws -> AppSettings {
        let source = FileManager.default.fileExists(atPath: file.path) ? file : legacy
        guard FileManager.default.fileExists(atPath: source.path) else { return .default }
        let data = try Data(contentsOf: source)
        var settings = source == legacy
            ? try JSONDecoder().decode(AppSettings.self, from: data)
            : try JSONDecoder().decode(Preferences.self, from: data).settings
        settings.token = ""
        settings.watchedRepositories = []
        return settings
    }
    func save(_ settings: AppSettings, lifetime: AccountSessionLifetime? = nil) throws {
        guard lifetime?.isActive != false else { throw CancellationError() }
        // Do not overwrite corrupt existing preferences with silently recovered defaults.
        _ = try load()
        var sanitized = settings
        sanitized.token = ""
        sanitized.watchedRepositories = []
        guard lifetime?.isActive != false else { throw CancellationError() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Preferences(sanitized)).write(to: file, options: .atomic)
    }

    private struct Preferences: Codable {
        var refreshInterval: TimeInterval
        var refreshOnLaunch: Bool
        var notifyNeedsReview: Bool
        var notifyNewReviewRequests: Bool
        var quietHours: QuietHours?
        var snoozeDefaultHour: Int
        var digestCadence: DigestCadence

        init(_ settings: AppSettings) {
            refreshInterval = settings.refreshInterval
            refreshOnLaunch = settings.refreshOnLaunch
            notifyNeedsReview = settings.notifyNeedsReview
            notifyNewReviewRequests = settings.notifyNewReviewRequests
            quietHours = settings.quietHours
            snoozeDefaultHour = settings.snoozeDefaultHour
            digestCadence = settings.digestCadence
        }

        var settings: AppSettings {
            AppSettings(token: "", refreshInterval: refreshInterval, refreshOnLaunch: refreshOnLaunch,
                        notifyNeedsReview: notifyNeedsReview, notifyNewReviewRequests: notifyNewReviewRequests,
                        quietHours: quietHours, snoozeDefaultHour: snoozeDefaultHour,
                        digestCadence: digestCadence, watchedRepositories: [])
        }
    }
}
