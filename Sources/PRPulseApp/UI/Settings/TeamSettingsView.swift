import SwiftUI

struct TeamPickerView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Team", selection: Binding(get: { viewModel.settings.selectedTeam }, set: { viewModel.selectTeam($0) })) {
                Text("Select a team").tag(Optional<GitHubTeam>.none)
                ForEach(teams) { team in Text("\(team.id) — \(team.name)").tag(Optional(team)) }
            }
            .accessibilityIdentifier("prpulse.team-picker")
            if viewModel.isLoadingTeams { ProgressView("Loading teams…").controlSize(.small) }
            if let error = viewModel.teamError { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if viewModel.availableTeams.isEmpty && !viewModel.isLoadingTeams && viewModel.teamError == nil {
                Text("No visible teams returned. Check organization membership and token access, then reload teams.").font(.caption).foregroundStyle(.secondary)
            }
            if viewModel.settings.selectedTeam == nil {
                Text("Select a team to see PRs authored by its members across repositories this account can access.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Reload teams") { Task { await viewModel.loadTeams(force: true) } }.disabled(viewModel.isLoadingTeams)
        }
        .task { await viewModel.loadTeams() }
    }
    private var teams: [GitHubTeam] {
        GitHubTeam.pickerChoices(available: viewModel.availableTeams, selected: viewModel.settings.selectedTeam)
    }
}

struct TeamSettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var body: some View {
        Form {
            TeamPickerView(viewModel: viewModel)
            Text("Team PRs uses team membership, including child-team members, and searches for open PRs by each author. Repository access follows the active account. Load more to include additional authors and pages; counts cover loaded PRs only.")
                .font(.callout).foregroundStyle(.secondary)
            Text("GitHub search can return at most 1,000 PRs per author and may require a narrower scope for accounts with access to more than 10,000 repositories. Coverage warnings appear in the PR list.")
                .font(.callout).foregroundStyle(.secondary)
            Text("If teams are missing, check organization membership visibility, token read:org access, and organization SSO authorization. The selection is stored separately for each account.")
                .font(.callout).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}
