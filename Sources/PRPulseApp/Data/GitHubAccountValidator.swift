import Foundation

enum GitHubAccountValidator {
    static func validate(token: String) async throws -> VerifiedGitHubIdentity {
        struct User: Decodable { let id: Int64; let login: String }
        var request = URLRequest(url: GitHubAPIClient.apiURL("user"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GitHubClientError.invalidResponse }
        guard response.statusCode == 200 else {
            throw GitHubClientError.apiFailure("GitHub could not verify this token (HTTP \(response.statusCode)). Check expiration and permissions.")
        }
        let user = try JSONDecoder().decode(User.self, from: data)
        let viewer = try await GitHubAPIClient(tokenProvider: { token }).fetchViewer()
        guard !viewer.isEmpty, viewer.caseInsensitiveCompare(user.login) == .orderedSame else {
            throw GitHubClientError.apiFailure("GitHub returned inconsistent account identities. Please retry.")
        }
        return VerifiedGitHubIdentity(id: String(user.id), login: viewer)
    }
}
