import AppKit
import SwiftUI

enum RepositoryPreferenceValidation {
    static func canAdd(_ candidate: String, to repositories: [RepositorySubscription]) -> Bool {
        let normalizedCandidate = normalizedName(candidate)
        guard isValidRepositoryName(normalizedCandidate) else { return false }

        return !repositories.contains {
            normalizedName($0.nameWithOwner).caseInsensitiveCompare(normalizedCandidate) == .orderedSame
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isValidRepositoryName(_ name: String) -> Bool {
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2 else { return false }

        return containsOnly(String(components[0]), allowedCharacters: ownerCharacters)
            && containsOnly(String(components[1]), allowedCharacters: repositoryCharacters)
    }

    private static func containsOnly(_ value: String, allowedCharacters: CharacterSet) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy(allowedCharacters.contains)
    }

    private static let ownerCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
    private static let repositoryCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
}

struct RefreshSettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Form {
            Section("Automatic refresh") {
                Toggle("Refresh on launch", isOn: Binding(
                    get: { viewModel.settings.refreshOnLaunch },
                    set: { viewModel.settings.refreshOnLaunch = $0 }
                ))

                Stepper(
                    value: Binding(
                        get: { Int(viewModel.settings.refreshInterval) },
                        set: { viewModel.settings.refreshInterval = TimeInterval($0) }
                    ),
                    in: 60...3600,
                    step: 60
                ) {
                    Text("Refresh every \(viewModel.currentRefreshIntervalMinutes) min")
                }

                Text("PRPulse checks for changes at this interval while it is running.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }
}

struct NotificationSettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Form {
            Section("Pull request alerts") {
                Toggle("Needs re-review", isOn: Binding(
                    get: { viewModel.settings.notifyNeedsReview },
                    set: { viewModel.settings.notifyNeedsReview = $0 }
                ))
                Toggle("New review requests", isOn: Binding(
                    get: { viewModel.settings.notifyNewReviewRequests },
                    set: { viewModel.settings.notifyNewReviewRequests = $0 }
                ))

                Text("Receive alerts when a pull request needs your attention.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Digest") {
                Picker("Digest cadence", selection: Binding(
                    get: { viewModel.settings.digestCadence },
                    set: { viewModel.settings.digestCadence = $0 }
                )) {
                    ForEach(DigestCadence.allCases) { cadence in
                        Text(cadence.rawValue.capitalized).tag(cadence)
                    }
                }

                Text("Choose how often PRPulse summarizes your pull request activity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }
}

struct RepositoriesSettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var newRepository = ""

    var body: some View {
        Form {
            Section("Watched repositories") {
                if viewModel.settings.watchedRepositories.isEmpty {
                    Text("Add repositories to receive their pull request updates.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.settings.watchedRepositories) { repository in
                        Toggle(repository.nameWithOwner, isOn: binding(for: repository))
                    }
                }
            }

            Section("Add repository") {
                HStack {
                    TextField("owner/repo", text: $newRepository)
                        .textFieldStyle(.roundedBorder)
                    Button("Add", action: addRepository)
                        .disabled(!canAddRepository)
                }

                Text("Enter the repository’s GitHub owner and name.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }

    private var trimmedRepository: String {
        newRepository.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddRepository: Bool {
        RepositoryPreferenceValidation.canAdd(
            trimmedRepository,
            to: viewModel.settings.watchedRepositories
        )
    }

    private func addRepository() {
        guard canAddRepository else { return }
        viewModel.settings.watchedRepositories.append(
            RepositorySubscription(nameWithOwner: trimmedRepository, notificationsEnabled: true)
        )
        newRepository = ""
    }

    private func binding(for repository: RepositorySubscription) -> Binding<Bool> {
        Binding(
            get: { repository.notificationsEnabled },
            set: { enabled in
                guard let index = viewModel.settings.watchedRepositories.firstIndex(of: repository) else { return }
                viewModel.settings.watchedRepositories[index].notificationsEnabled = enabled
            }
        )
    }
}

struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Form {
            Section("Tools") {
                Button("Test Notification") {
                    viewModel.testNotification()
                }
                Button("Force Digest Recompute") {
                    viewModel.forceDigestRecompute()
                }
                Button("Refresh Now") {
                    viewModel.refreshNow()
                }
            }

            Section("Support") {
                Button("Open settings.json") {
                    Task { await viewModel.openSettingsJSON() }
                }
                Button("Copy viewer login") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.viewerLogin, forType: .string)
                }
                Button("Export logs") {
                    Task { await viewModel.exportDiagnostics() }
                }

                Text("Exported diagnostics omit your GitHub token.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }
}
