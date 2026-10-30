import Foundation
import XCTest
@testable import PRPulseApp

final class GitHubCITests: XCTestCase {
    func testOverlappingCIReadsShareRequestsButLaterReadsStayFresh() async throws {
        let mode = "perf-\(UUID().uuidString)"
        let api = client(mode)
        let request = pr
        async let a = api.fetchCI(for: request)
        async let b = api.fetchCI(for: request)
        async let c = api.fetchCI(for: request)
        async let d = api.fetchCI(for: request)
        let values = try await [a, b, c, d]
        XCTAssertTrue(values.allSatisfy { $0.state == .failed })
        XCTAssertEqual(CIProtocol.counts.count("Bearer \(mode)"), 3, "Overlapping reads should share one snapshot/context/revision sequence")
        _ = try await api.fetchCI(for: request)
        XCTAssertEqual(CIProtocol.counts.count("Bearer \(mode)"), 6, "Completed results must not become a stale cache")
        _ = try await api.revalidateCI(for: request)
        XCTAssertEqual(CIProtocol.counts.count("Bearer \(mode)"), 9, "Notification verification must always read live state")
        let otherAccount = client(mode)
        async let firstAccount = api.fetchCI(for: request)
        async let secondAccount = otherAccount.fetchCI(for: request)
        _ = try await [firstAccount, secondAccount]
        XCTAssertEqual(CIProtocol.counts.count("Bearer \(mode)"), 15, "Client/account instances must never share in-flight reads")
    }
    func testFailedCIReadIsRemovedBeforeRetry() async {
        let mode = "perf-changed-\(UUID().uuidString)"
        let api = client(mode)
        for _ in 0..<2 {
            do { _ = try await api.fetchCI(for: pr); XCTFail("Changed revision must fail") }
            catch { guard case GitHubClientError.obsoleteCI = error else { return XCTFail("Unexpected \(error)") } }
        }
        XCTAssertEqual(CIProtocol.counts.count("Bearer \(mode)"), 6, "A failed operation must not poison subsequent attempts")
    }
    func testOpenListsExcludeMergedRowsAndMergedPRReferences() async throws {
        for tab in [PullRequestTab.mine, .reviewRequested, .watched] {
            let page = try await client("lifecycle").fetchPullRequests(tab: tab, cursor: nil)
            XCTAssertEqual(page.items.map(\.id), ["PR_1"], "Drop stale merged search results and PRs merged before detail hydration")
            let refs = try XCTUnwrap(page.items.first).detail.linkedReferences
            XCTAssertEqual(refs.filter { $0.type == .pullRequest }.map(\.number), [11])
            XCTAssertEqual(refs.filter { $0.type == .issue }.map(\.number), [14], "Issue references remain intact")
        }
    }
    func testDiscoveryLeavesCapacityForLiveFailureVerification() async throws {
        let api = client("many")
        let page = try await api.fetchPullRequests(tab: .mine, cursor: nil)
        XCTAssertEqual(page.items.count, 15)
        let verified = try await api.revalidateCI(for: pr)
        XCTAssertTrue(verified.isComplete)
        XCTAssertEqual(verified.state, .failed)
    }
    func testRepeatedCIReadsDeferBeforeStarvingDashboardDiscovery() async throws {
        let api = client()
        var deferred = false
        for _ in 0..<12 {
            do { _ = try await api.fetchCI(for: pr) }
            catch { deferred = error.localizedDescription.contains("budget") }
        }
        XCTAssertTrue(deferred, "Initial reads and revalidation must share a bounded CI request allowance")
        let page = try await api.fetchPullRequests(tab: .mine, cursor: nil)
        XCTAssertEqual(page.items.count, 2, "Dashboard discovery remains usable after CI exhausts its own allowance")
        XCTAssertTrue(page.items.allSatisfy { $0.detail.ci?.warning?.contains("budget") == true })
    }
    func testExpectedStatusIsQueuedAndDoesNotSuppressOtherFailureObservation() async throws {
        let ci = try await client("expected").fetchCI(for: pr)
        XCTAssertEqual(ci.checks.first(where: { $0.name == "External CI" })?.state, .queued)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CIMonitorStore(directory: directory, lifetime: AccountSessionLifetime())
        var initial = ci; initial.checks.removeAll(where: { $0.state == .failure })
        _ = try store.observe(pr: pr, snapshot: initial)
        XCTAssertEqual(try store.observe(pr: pr, snapshot: ci).map(\.name), ["Build"])
    }
    func testSearchCapsAreListSpecificAndDoNotSuggestTokenAccessProblems() async throws {
        for (tab, label) in [(PullRequestTab.mine, "My PRs"), (.reviewRequested, "Reviews")] {
            let page = try await client("large").fetchPullRequests(tab: tab, cursor: nil)
            XCTAssertTrue(page.warnings.isEmpty)
            XCTAssertTrue(page.coverageWarning?.contains(label) ?? false)
        }
        let watched = try await client("large").fetchPullRequests(tab: .watched, cursor: nil)
        XCTAssertTrue(watched.warnings.isEmpty)
        XCTAssertNil(watched.coverageWarning)
    }
    func testSuccessfulRerunSupersedesOlderFailureWithoutMergingDifferentWorkflows() async throws {
        let rerun = try await client("rerun").fetchCI(for: pr)
        XCTAssertEqual(rerun.state, .passed)
        XCTAssertEqual(rerun.checks.map(\.id), ["C2"])
        let distinct = try await client("different-workflow").fetchCI(for: pr)
        XCTAssertEqual(distinct.state, .failed)
        XCTAssertEqual(distinct.checks.count, 2)
    }
    func testTestMergeChecksTakePrecedenceAndAllPagesAreDecoded() async throws {
        let ci = try await client().fetchCI(for: pr)
        XCTAssertEqual(ci.headSHA, "head")
        XCTAssertEqual(ci.revision, "merge")
        XCTAssertEqual(ci.checks.map(\.name), ["Build", "External CI"])
        XCTAssertEqual(ci.state, .failed)
        XCTAssertTrue(ci.isComplete)
        XCTAssertEqual(ci.checks.first?.url?.absoluteString, "https://github.com/example/repo/actions/runs/1")
    }
    func testRevisionChangeDiscardsObsoleteResults() async {
        do { _ = try await client("changed").fetchCI(for: pr); XCTFail("Stale revision must be discarded") }
        catch { guard case GitHubClientError.obsoleteCI = error else { return XCTFail("Unexpected \(error)") } }
    }
    func testPartialErrorsDoNotImplySuccessfulCoverage() async throws {
        let ci = try await client("partial").fetchCI(for: pr)
        XCTAssertFalse(ci.isComplete)
        XCTAssertNotNil(ci.warning)
    }
    func testOneChangingPRDoesNotDiscardOtherPRsOnThePage() async throws {
        let page = try await client("page-race").fetchPullRequests(tab: .mine, cursor: nil)
        XCTAssertEqual(page.items.map(\.id), ["PR_1", "PR_2"])
        XCTAssertFalse(page.items[0].detail.ci?.isComplete ?? true)
        XCTAssertEqual(page.items[1].detail.ci?.state, .failed)
    }
    func testRateLimitStopsSubsequentRequestsUntilRetry() async {
        let client = client("limited")
        for _ in 0..<2 {
            do { _ = try await client.fetchCI(for: pr); XCTFail("Rate limit must throw") }
            catch { guard case GitHubClientError.rateLimited(let until) = error else { return XCTFail("Unexpected \(error)") }
                XCTAssertGreaterThan(until.timeIntervalSinceNow, 50)
            }
        }
    }
    private var pr: PullRequest {
        .init(id: "PR_1", number: 1, title: "CI", url: URL(string: "https://github.com/example/repo/pull/1")!,
              repository: .init(nameWithOwner: "example/repo"), author: .init(login: "me"),
              createdAt: Date(), updatedAt: Date(), isDraft: false)
    }
    private func client(_ mode: String = "normal") -> GitHubAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CIProtocol.self]
        return GitHubAPIClient(session: URLSession(configuration: configuration), tokenProvider: { mode },
                               watchedRepositoriesProvider: { [.init(nameWithOwner: "example/repo", notificationsEnabled: true)] })
    }
}

private final class CIProtocol: URLProtocol, @unchecked Sendable {
    static let counts = RequestCounts()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; body.append(buffer, count: count)
            }
        }
        let raw = String(decoding: body, as: UTF8.self)
        let mode = request.value(forHTTPHeaderField: "Authorization") ?? ""
        if mode.contains("perf-") {
            Self.counts.record(mode)
            Thread.sleep(forTimeInterval: 0.02)
        }
        let variables = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["variables"] as? [String: Any]
        func suite(_ name: String) -> [String: Any] {
            ["createdAt": "2026-10-01T00:00:00Z", "app": ["id": "APP"], "workflowRun": ["event": "pull_request", "workflow": ["name": name]]]
        }
        let check: [String: Any] = ["__typename": "CheckRun", "id": "C1", "name": "Build", "status": "COMPLETED",
                                   "conclusion": "FAILURE", "detailsUrl": "https://github.com/example/repo/actions/runs/1",
                                   "startedAt": "2026-10-01T00:00:00Z", "completedAt": "2026-10-01T00:01:00Z", "checkSuite": suite("Build workflow")]
        func commit(_ id: String, _ oid: String, _ checks: [[String: Any]], more: Bool = false) -> [String: Any] {
            ["id": id, "oid": oid, "statusCheckRollup": ["contexts": ["nodes": checks, "pageInfo": ["hasNextPage": more, "endCursor": more ? "page2" as Any : NSNull()]]]]
        }
        var result: [String: Any]
        if raw.contains("query SearchPRs") {
            let nodes: [[String: Any]] = (1...(mode.contains("many") ? 15 : mode.contains("lifecycle") ? 3 : 2)).map { index in
                ["id": "PR_\(index)", "number": index, "title": "Tests", "url": "https://github.com/example/repo/pull/\(index)",
                 "state": mode.contains("lifecycle") && index == 2 ? "MERGED" : "OPEN",
                 "createdAt": "2026-10-01T00:00:00Z", "updatedAt": "2026-10-01T00:00:00Z", "isDraft": false,
                 "author": ["login": "me"], "repository": ["nameWithOwner": "example/repo"]]
            }
            result = ["data": ["search": ["issueCount": mode.contains("large") ? 1001 : 2, "nodes": mode.contains("large") ? [] : nodes, "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]]]]
        } else if raw.contains("query PRDetails") {
            if mode.contains("lifecycle") {
                let references: [[String: Any]] = [(11, "OPEN"), (12, "MERGED"), (13, "CLOSED")].map { number, state in
                    ["source": ["__typename": "PullRequest", "number": number, "state": state,
                                "url": "https://github.com/example/repo/pull/\(number)", "repository": ["nameWithOwner": "example/repo"]]]
                } + [["source": ["__typename": "Issue", "number": 14, "url": "https://github.com/example/repo/issues/14", "repository": ["nameWithOwner": "example/repo"]]]]
                result = ["data": ["nodes": [["id": "PR_1", "state": "OPEN", "timelineItems": ["nodes": references]],
                                              ["id": "PR_3", "state": "MERGED"]]]]
            } else { result = ["data": ["nodes": []]] }
        } else if raw.contains("query PRCIRevision") {
            let changed = mode.contains("changed") || (mode.contains("page-race") && variables?["id"] as? String == "PR_1")
            result = ["data": ["node": ["state": "OPEN", "headRefOid": changed ? "new" : "head",
                                       "potentialMergeCommit": ["id": "M", "oid": "merge"]]]]
        } else if raw.contains("query CIContexts") {
            var checks: [[String: Any]] = [["__typename": "StatusContext", "id": "S1", "context": "External CI", "state": mode.contains("expected") ? "EXPECTED" : "SUCCESS", "targetUrl": "https://ci.example.com/1", "createdAt": "2026-10-01T00:01:00Z"]]
            if mode.contains("rerun") || mode.contains("different-workflow") {
                var latest = check
                latest["id"] = "C2"; latest["conclusion"] = "SUCCESS"; latest["startedAt"] = "2026-10-01T00:02:00Z"
                latest["checkSuite"] = suite(mode.contains("different-workflow") ? "Other workflow" : "Build workflow")
                checks = [latest]
            }
            result = ["data": ["node": commit("M", "merge", checks)]]
        } else {
            result = ["data": ["node": ["state": "OPEN", "headRefOid": "head", "commits": ["nodes": [["commit": commit("H", "head", [])]]],
                                       "potentialMergeCommit": commit("M", "merge", [check], more: true)]]]
        }
        if mode.contains("partial") { result["errors"] = [["message": "Check permission denied"]] }
        let limited = mode.contains("limited")
        let response = HTTPURLResponse(url: request.url!, statusCode: limited ? 429 : 200, httpVersion: nil,
                                       headerFields: limited ? ["Retry-After": "60"] : ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: result)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class RequestCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    func record(_ key: String) { lock.lock(); defer { lock.unlock() }; values[key, default: 0] += 1 }
    func count(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[key, default: 0] }
}
