import Foundation
import XCTest
@testable import PRPulseApp

final class GitHubTeamTests: XCTestCase {
    private let team = GitHubTeam(organization: "example", slug: "platform", name: "Platform")

    func testMembershipPaginationAndAuthorSearchAcrossPages() async throws {
        let client = makeClient()
        let first = try await client.fetchTeamPullRequests(team: team, cursor: nil)
        XCTAssertEqual(first.items.map(\.author.login), ["alice"])
        XCTAssertEqual(first.items.map(\.repository.nameWithOwner), ["example/project"])
        XCTAssertTrue(first.hasNextPage)
        XCTAssertTrue(first.coverageWarning?.contains("1 of 2 members") == true)
        let second = try await client.fetchTeamPullRequests(team: team, cursor: first.cursor)
        XCTAssertEqual(second.items.map(\.author.login), ["bob"])
        XCTAssertFalse((first.items + second.items).contains { $0.author.login == "outsider" })
        XCTAssertFalse(second.hasNextPage)
        XCTAssertTrue(second.coverageWarning?.contains("All members searched") == true)
    }

    func testTeamCursorCannotBeReusedForAnotherSelection() async throws {
        let client = makeClient()
        let page = try await client.fetchTeamPullRequests(team: team, cursor: nil)
        do {
            _ = try await client.fetchTeamPullRequests(team: GitHubTeam(organization: "other", slug: "team", name: "Other"), cursor: page.cursor)
            XCTFail("A cursor must belong to the selected team")
        } catch { XCTAssertTrue(error is GitHubClientError) }
    }

    func testRepeatedMembershipCursorFailsInsteadOfLooping() async throws {
        do {
            _ = try await makeClient(token: "cycle").fetchTeamPullRequests(team: team, cursor: nil)
            XCTFail("Repeated membership cursors must fail")
        } catch { XCTAssertTrue(error is GitHubClientError) }
    }

    func testMissingTeamExplainsMembershipAccess() async throws {
        do {
            _ = try await makeClient(token: "missing").fetchTeamPullRequests(team: team, cursor: nil)
            XCTFail("Missing or inaccessible teams must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("organization membership read access")) }
    }

    func testSelectionRoundTripsAndLegacySettingsDecode() throws {
        var settings = AppSettings.default
        settings.selectedTeam = team
        let encoded = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: encoded).selectedTeam, team)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "selectedTeam")
        XCTAssertNil(try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object)).selectedTeam)
    }


    func testManagedUserLoginIsSearchedAndReturnsAuthoredPR() async throws {
        let page = try await makeClient(token: "managed").fetchTeamPullRequests(team: team, cursor: nil)
        XCTAssertEqual(page.items.map(\.author.login), ["mona-cat_octo"])
        XCTAssertFalse(page.hasNextPage)
    }

    func testAuthorLoginLengthAndSearchMetacharactersAreRejected() async throws {
        for login in [String(repeating: "a", count: 40), "alice is:closed", "alice:foo", "alice+foo"] {
            do {
                _ = try await makeClient(token: "login:" + login).fetchTeamPullRequests(team: team, cursor: nil)
                XCTFail("Unsafe or overlength login should fail: \(login)")
            } catch { XCTAssertTrue(error is GitHubClientError) }
        }
        let maximum = String(repeating: "a", count: 34) + "_octo"
        let page = try await makeClient(token: "login:" + maximum).fetchTeamPullRequests(team: team, cursor: nil)
        XCTAssertEqual(page.items.map(\.author.login), [maximum])
    }

    func testRenamedTeamHasStableSelectionIdentityAndOnePickerChoice() {
        let renamed = GitHubTeam(organization: team.organization, slug: team.slug, name: "Renamed Platform")
        XCTAssertEqual(team, renamed)
        XCTAssertEqual(Set([team, renamed]).count, 1)
        let choices = GitHubTeam.pickerChoices(available: [renamed, renamed], selected: team)
        XCTAssertEqual(choices.count, 1)
        XCTAssertEqual(choices.first?.name, renamed.name)
        XCTAssertEqual(GitHubTeam.pickerChoices(available: [], selected: team).map(\.id), [team.id])
    }

    func testDirectoryPaginatesTeams() async throws {
        let teams = try await makeClient().fetchTeams()
        XCTAssertEqual(teams.map(\.id), ["example/platform", "example/tools"])
    }

    private func makeClient(token: String = "test") -> GitHubAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TeamResponseProtocol.self]
        return GitHubAPIClient(session: URLSession(configuration: configuration), tokenProvider: { token })
    }
}

private final class TeamResponseProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open(); defer { stream.close() }
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                result.append(buffer, count: count)
            }
            return result
        } ?? Data()
        let text = String(decoding: body, as: UTF8.self)
        let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let variables = payload?["variables"] as? [String: Any] ?? [:]
        let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let json: String
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer missing" {
            json = #"{"data":{"organization":{"team":null}}}"#
        } else if text.contains("TeamDirectory") {
            json = #"{"data":{"viewer":{"organizations":{"nodes":[{"login":"example"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}"#
        } else if text.contains("OrganizationTeams") {
            json = variables["after"] as? String == "teams-next"
                ? #"{"data":{"organization":{"teams":{"nodes":[{"slug":"tools","name":"Tools"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}"#
                : #"{"data":{"organization":{"teams":{"nodes":[{"slug":"platform","name":"Platform"}],"pageInfo":{"hasNextPage":true,"endCursor":"teams-next"}}}}}"#
        } else if authorization == "Bearer managed" || authorization.hasPrefix("Bearer login:") {
            let login = authorization == "Bearer managed" ? "mona-cat_octo" : String(authorization.dropFirst("Bearer login:".count))
            if text.contains("TeamMembers") {
                let object: [String: Any] = ["data": ["organization": ["team": ["members": ["nodes": [["login": login]], "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]]]]]]
                json = String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            } else if text.contains("SearchPRs") { json = Self.searchResponse(author: login) }
            else { json = #"{"data":{"nodes":[]}}"# }
        } else if text.contains("TeamMembers") {
            let cycle = request.value(forHTTPHeaderField: "Authorization") == "Bearer cycle"
            let second = text.contains("members-next") && !cycle
            json = second
                ? #"{"data":{"organization":{"team":{"members":{"nodes":[{"login":"bob"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}"#
                : #"{"data":{"organization":{"team":{"members":{"nodes":[{"login":"alice"}],"pageInfo":{"hasNextPage":true,"endCursor":"members-next"}}}}}}"#
        } else if text.contains("SearchPRs") {
            // Author qualifiers, rather than team-review-requested, define Team PRs.
            guard text.contains("author:alice") || text.contains("author:bob"), !text.contains("review-requested") else {
                client?.urlProtocol(self, didFailWithError: GitHubClientError.invalidResponse)
                return
            }
            json = Self.searchResponse(author: text.contains("author:alice") ? "alice" : "bob")
        } else { json = #"{"data":{"nodes":[]}}"# }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    private static func searchResponse(author: String) -> String {
        let rows: [[String: Any]] = [author, "outsider"].map { login in
            ["id": "PR_" + login, "state": "OPEN", "number": login == "alice" ? 7 : 8,
             "title": "Authored by " + login, "url": "https://github.com/example/project/pull/7",
             "createdAt": "2026-10-01T00:00:00Z", "updatedAt": "2026-10-01T00:00:00Z", "isDraft": false,
             "author": ["login": login], "repository": ["nameWithOwner": "example/project"]]
        }
        let matching = rows.filter { ($0["author"] as? [String: String])?["login"] == author }
        let object: [String: Any] = ["data": ["search": ["issueCount": matching.count, "nodes": matching, "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    override func stopLoading() {}
}
