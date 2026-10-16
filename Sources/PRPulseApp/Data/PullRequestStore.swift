import Foundation

actor PullRequestStore {
    nonisolated let directory: URL
    nonisolated let lifetime = AccountSessionLifetime()
    private let globalPreferences: GlobalPreferencesStore?
    private let repositoriesURL: URL
    private var retired = false
    private let corruptFiles: Set<String>
    func retire() { lifetime.invalidate(); retired = true }
    private let overridesURL: URL
    private let ledgerURL: URL
    private let settingsURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private var overrides: [String: PullRequestOverride]
    private var notificationLedger: [String: Date]
    private var settings: AppSettings
    private var activityEvents: [ActivityEvent]
    private let activityURL: URL

    init(
        directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PRPulseApp", isDirectory: true),
        globalPreferences: GlobalPreferencesStore? = nil
    ) {
        self.directory = directory
        self.globalPreferences = globalPreferences
        self.repositoriesURL = directory.appendingPathComponent("repositories.json")
        self.overridesURL = directory.appendingPathComponent("overrides.json")
        self.ledgerURL = directory.appendingPathComponent("ledger.json")
        self.settingsURL = directory.appendingPathComponent("settings.json")
        self.activityURL = directory.appendingPathComponent("activity.json")

        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let decoder = JSONDecoder()
        var invalid = Set<String>()
        func read<T: Decodable>(_ type: T.Type, at url: URL, fallback: T) -> T {
            guard fm.fileExists(atPath: url.path) else { return fallback }
            do { return try decoder.decode(type, from: Data(contentsOf: url)) }
            catch { invalid.insert(url.lastPathComponent); return fallback }
        }
        self.overrides = read([String: PullRequestOverride].self, at: overridesURL, fallback: [:])
        self.notificationLedger = read([String: Date].self, at: ledgerURL, fallback: [:])
        var decoded = read(AppSettings.self, at: settingsURL, fallback: .default)
        decoded.token = "" // never load token from disk
        if fm.fileExists(atPath: repositoriesURL.path) {
            decoded.watchedRepositories = read([RepositorySubscription].self, at: repositoriesURL, fallback: [])
        }
        self.settings = decoded
        self.activityEvents = read([ActivityEvent].self, at: activityURL, fallback: [])
        self.corruptFiles = invalid

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func override(for id: String) -> PullRequestOverride {
        overrides[id] ?? PullRequestOverride()
    }

    func saveOverride(_ value: PullRequestOverride, for id: String) async throws {
        guard !retired, lifetime.isActive else { throw CancellationError() }
        try checkWritable(overridesURL)
        var next = overrides
        next[id] = value
        try encoder.encode(next).write(to: overridesURL, options: .atomic)
        overrides = next
    }

    func ledgerTimestamp(for key: String) -> Date? {
        notificationLedger[key]
    }

    func updateLedger(date: Date, for key: String) async throws {
        guard !retired, lifetime.isActive else { throw CancellationError() }
        try checkWritable(ledgerURL)
        var next = notificationLedger
        next[key] = date
        try encoder.encode(next).write(to: ledgerURL, options: .atomic)
        notificationLedger = next
    }

    func loadSettings() async -> AppSettings {
        if let globalPreferences, var global = try? await globalPreferences.load() {
            global.watchedRepositories = settings.watchedRepositories
            return global
        }
        return settings
    }

    func save(settings newSettings: AppSettings) async throws {
        guard !retired, lifetime.isActive else { throw CancellationError() }
        try checkWritable(globalPreferences == nil ? settingsURL : repositoriesURL)
        if let globalPreferences {
            try await globalPreferences.save(newSettings, lifetime: lifetime)
            guard !retired, lifetime.isActive else { throw CancellationError() }
            try encoder.encode(newSettings.watchedRepositories).write(to: repositoriesURL, options: .atomic)
            settings = newSettings
            return
        }
        var sanitized = newSettings
        sanitized.token = ""
        try encoder.encode(sanitized).write(to: settingsURL, options: .atomic)
        settings = sanitized
    }

    func appendActivity(_ event: ActivityEvent) async throws {
        guard !retired, lifetime.isActive else { throw CancellationError() }
        try checkWritable(activityURL)
        let next = activityEvents + [event]
        try encoder.encode(next).write(to: activityURL, options: .atomic)
        activityEvents = next
    }

    func recentActivity(since date: Date) -> [ActivityEvent] {
        activityEvents.filter { $0.date >= date }
    }

    func storageWarning() async -> String? {
        if !corruptFiles.isEmpty { return "Some local account data could not be read. Original files are preserved; affected data is read-only until repaired." }
        if let globalPreferences {
            do { _ = try await globalPreferences.load() }
            catch { return "Shared preferences could not be read. The original file is preserved." }
        }
        return nil
    }

    private func checkWritable(_ url: URL) throws {
        guard !corruptFiles.contains(url.lastPathComponent) else { throw CocoaError(.fileReadCorruptFile) }
    }

    private func persistOverrides() throws {
        let data = try encoder.encode(overrides)
        try data.write(to: overridesURL, options: .atomic)
    }

    private func persistLedger() throws {
        let data = try encoder.encode(notificationLedger)
        try data.write(to: ledgerURL, options: .atomic)
    }

    private func persistSettings() throws {
        var sanitized = settings
        sanitized.token = "" // never persist token to disk
        let data = try encoder.encode(sanitized)
        try data.write(to: settingsURL, options: .atomic)
    }

    private func persistActivity() throws {
        let data = try encoder.encode(activityEvents)
        try data.write(to: activityURL, options: .atomic)
    }
}
