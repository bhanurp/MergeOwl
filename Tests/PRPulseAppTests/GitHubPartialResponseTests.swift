import Foundation
import XCTest
@testable import PRPulseApp

final class GitHubPartialResponseTests: XCTestCase {
    func testAccessRestrictionsAreWarningsButInvalidCredentialsAreNot() {
        XCTAssertTrue(GitHubClientError.graphQLErrors(["Resource protected by organization SAML enforcement"]).isAccessRestriction)
        XCTAssertTrue(GitHubClientError.apiFailure("Resource not accessible by personal access token").isAccessRestriction)
        XCTAssertFalse(GitHubClientError.apiFailure("Bad credentials").isAccessRestriction)
        XCTAssertFalse(GitHubClientError.graphQLErrors(["SAML enforcement", "Invalid query"]).isAccessRestriction)
    }
    func testSearchPreservesAccessiblePRsAndWarnings() async throws {
        let client = makeClient()
        let page = try await client.fetchPullRequests(tab: .mine, cursor: nil)
        XCTAssertEqual(page.items.map(\.number), [7])
        XCTAssertEqual(page.warnings, ["Organization requires SAML authorization"])
    }

    func testAuthenticationFailureStillThrows() async {
        let client = makeClient(token: "invalid")
        do {
            _ = try await client.fetchViewer()
            XCTFail("Invalid credentials must remain an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Bad credentials")
        }
    }

    private func makeClient(token: String = "test") -> GitHubAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PartialResponseProtocol.self]
        return GitHubAPIClient(session: URLSession(configuration: configuration), tokenProvider: { token })
    }
}

private final class PartialResponseProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let invalid = request.value(forHTTPHeaderField: "Authorization") == "Bearer invalid"
        let body = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                result.append(buffer, count: count)
            }
            return result
        } ?? Data()
        let query = String(decoding: body, as: UTF8.self)
        let json: String
        if invalid {
            json = #"{"message":"Bad credentials"}"#
        } else if query.contains("SearchPRs") {
            json = #"{"data":{"search":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[null,{"id":"PR_7","number":7,"title":"Accessible PR","url":"https://github.com/example/repo/pull/7","createdAt":"2026-10-01T00:00:00Z","updatedAt":"2026-10-01T00:00:00Z","isDraft":false,"author":{"login":"test"},"repository":{"nameWithOwner":"example/repo"}}]}},"errors":[{"message":"Organization requires SAML authorization"},{"message":"Organization requires SAML authorization"}]}"#
        } else {
            json = #"{"data":{"nodes":[]}}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: invalid ? 401 : 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
