import Foundation

struct GitHubTeam: Codable, Hashable, Identifiable {
    let organization: String
    let slug: String
    let name: String
    var id: String { "\(organization)/\(slug)" }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func pickerChoices(available: [Self], selected: Self?) -> [Self] {
        var seen = Set<String>()
        var choices = available.filter { seen.insert($0.id).inserted }
        if let selected, seen.insert(selected.id).inserted { choices.append(selected) }
        return choices
    }
}

extension GitHubAPIClient {
    nonisolated(nonsending) func fetchTeams() async throws -> [GitHubTeam] {
        var teams: [GitHubTeam] = []
        var after: String?
        var seenOrganizations = Set<String>()
        repeat {
            let (data, warnings): (TeamDirectoryData, [String]) = try await performGraphQLResult(query: """
            query TeamDirectory($after: String) {
              viewer { organizations(first: 100, after: $after) {
                pageInfo { hasNextPage endCursor }
                nodes { login }
              } }
            }
            """, variables: TeamAfter(after: after))
            guard warnings.isEmpty else { throw GitHubClientError.graphQLErrors(warnings) }
            for organization in data.viewer.organizations.nodes {
                var teamAfter: String?
                var seenTeams = Set<String>()
                repeat {
                    let (result, warnings): (OrganizationTeamsData, [String]) = try await performGraphQLResult(query: """
                    query OrganizationTeams($organization: String!, $after: String) {
                      organization(login: $organization) { teams(first: 100, after: $after) {
                        pageInfo { hasNextPage endCursor }
                        nodes { slug name }
                      } }
                    }
                    """, variables: OrganizationTeamVariables(organization: organization.login, after: teamAfter))
                    guard warnings.isEmpty else { throw GitHubClientError.graphQLErrors(warnings) }
                    guard let connection = result.organization?.teams else { throw Self.teamAccessError }
                    teams += connection.nodes.map { GitHubTeam(organization: organization.login, slug: $0.slug, name: $0.name) }
                    teamAfter = try connection.pageInfo.nextCursor()
                    if let teamAfter, !seenTeams.insert(teamAfter).inserted { throw GitHubClientError.invalidResponse }
                } while teamAfter != nil
            }
            after = try data.viewer.organizations.pageInfo.nextCursor()
            if let after, !seenOrganizations.insert(after).inserted { throw GitHubClientError.invalidResponse }
        } while after != nil
        return teams.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    nonisolated(nonsending) func fetchTeamPullRequests(team: GitHubTeam, cursor: String?) async throws -> PullRequestPage {
        var position: TeamSearchCursor
        if let cursor {
            guard let data = Data(base64Encoded: cursor), let decoded = try? JSONDecoder().decode(TeamSearchCursor.self, from: data), decoded.teamID == team.id, decoded.index >= 0, decoded.index < decoded.authors.count else { throw GitHubClientError.invalidResponse }
            position = decoded
        } else {
            var members: [String] = []
            var after: String?
            var seenMembers = Set<String>()
            repeat {
                let (data, warnings): (TeamMembersData, [String]) = try await performGraphQLResult(query: """
                query TeamMembers($organization: String!, $slug: String!, $after: String) {
                  organization(login: $organization) { team(slug: $slug) {
                    members(first: 100, after: $after) {
                      pageInfo { hasNextPage endCursor }
                      nodes { login }
                    }
                  } }
                }
                """, variables: TeamMemberVariables(organization: team.organization, slug: team.slug, after: after))
                guard warnings.isEmpty else { throw GitHubClientError.graphQLErrors(warnings) }
                guard let connection = data.organization?.team?.members else { throw Self.teamAccessError }
                members += connection.nodes.map(\.login)
                after = try connection.pageInfo.nextCursor()
                if let after, !seenMembers.insert(after).inserted { throw GitHubClientError.invalidResponse }
            } while after != nil
            position = TeamSearchCursor(teamID: team.id, authors: Array(Set(members)).sorted(), index: 0, after: nil, limitedAuthors: [])
        }
        guard !position.authors.isEmpty else { return PullRequestPage(items: [], cursor: nil, hasNextPage: false) }
        // Managed-user logins include an underscore/enterprise shortcode within the 39-character limit.
        // Absolute anchors also reject trailing line breaks and other search syntax.
        guard position.authors.allSatisfy({ $0.range(of: "\\A[A-Za-z0-9][A-Za-z0-9_-]{0,38}\\z", options: .regularExpression) != nil }) else { throw GitHubClientError.invalidResponse }
        // Each author is a separate search: no query-length or boolean-clause truncation for large teams.
        var page = try await fetchSearchPage(query: "is:pr is:open author:\(position.authors[position.index]) sort:updated-desc", cursor: position.after, scope: .team)
        if page.coverageWarning != nil { position.limitedAuthors.append(position.authors[position.index]) }
        if page.hasNextPage {
            guard let next = page.cursor, next != position.after else { throw GitHubClientError.invalidResponse }
            position.after = next
        } else { position.index += 1; position.after = nil }
        page.hasNextPage = position.index < position.authors.count
        page.cursor = page.hasNextPage ? try JSONEncoder().encode(position).base64EncodedString() : nil
        let progress = "Team PRs: searched \(min(position.index + (position.after == nil ? 0 : 1), position.authors.count)) of \(position.authors.count) members. \(page.hasNextPage ? "Load more for additional members and pages; order covers loaded PRs only." : "All members searched; only repositories accessible to this account are included.")"
        let limit = position.limitedAuthors.isEmpty ? nil : "GitHub search returns at most 1,000 PRs per author. Coverage is incomplete for: \(Set(position.limitedAuthors).sorted().joined(separator: ", "))."
        page.coverageWarning = [limit, progress].compactMap { $0 }.joined(separator: " ")
        return try await enrich(page)
    }

    private static var teamAccessError: GitHubClientError {
        .apiFailure("Team membership is unavailable. Check that the team still exists, your account can view it, and your token has organization membership read access (read:org for classic tokens). Authorize organization SSO if required.")
    }
}

private struct TeamSearchCursor: Codable { var teamID: String; var authors: [String]; var index: Int; var after: String?; var limitedAuthors: [String] }
private struct TeamAfter: Encodable { let after: String? }
private struct OrganizationTeamVariables: Encodable { let organization: String; let after: String? }
private struct TeamMemberVariables: Encodable { let organization: String; let slug: String; let after: String? }
private struct TeamPageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
    func nextCursor() throws -> String? {
        guard hasNextPage else { return nil }
        guard let endCursor, !endCursor.isEmpty else { throw GitHubClientError.invalidResponse }
        return endCursor
    }
}
private struct TeamConnection<Node: Decodable>: Decodable { let nodes: [Node]; let pageInfo: TeamPageInfo }
private struct TeamLogin: Decodable { let login: String }
private struct TeamDirectoryData: Decodable {
    struct Viewer: Decodable { let organizations: TeamConnection<TeamLogin> }
    let viewer: Viewer
}
private struct OrganizationTeamsData: Decodable {
    struct TeamNode: Decodable { let slug: String; let name: String }
    struct Organization: Decodable { let teams: TeamConnection<TeamNode> }
    let organization: Organization?
}
private struct TeamMembersData: Decodable {
    struct Team: Decodable { let members: TeamConnection<TeamLogin> }
    struct Organization: Decodable { let team: Team? }
    let organization: Organization?
}
