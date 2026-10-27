import Foundation

actor GitHubRequestGate {
    private var blockedUntil: Date?
    func check() throws {
        if let blockedUntil, blockedUntil > Date() { throw GitHubClientError.rateLimited(blockedUntil) }
    }
    func deferUntil(_ date: Date) { blockedUntil = date }
}

extension GitHubAPIClient {
    nonisolated(nonsending) func fetchCI(for pullRequest: PullRequest) async throws -> CIStatus {
        let variables = CIIDVariables(id: pullRequest.id)
        let (data, warnings): (CIPRData, [String]) = try await performGraphQLResult(query: Self.ciQuery, variables: variables)
        guard let pr = data.node, pr.state == "OPEN", let head = pr.headRefOid,
              let headCommit = pr.commits?.nodes?.last?.commit, headCommit.oid == head else { return .unavailable }
        // Test-merge results take precedence only when GitHub reports checks there.
        let merge = pr.potentialMergeCommit
        let applicable = merge?.statusCheckRollup != nil ? merge! : headCommit
        var snapshot = CIStatus(headSHA: head, revision: applicable.oid, checks: [], isComplete: warnings.isEmpty)
        var connection = applicable.statusCheckRollup?.contexts
        var seen = Set<String>()
        var contexts: [CIContext] = []
        while let page = connection {
            contexts += page.nodes.compactMap { $0 }
            if page.nodes.contains(where: { $0 == nil }) { snapshot.isComplete = false }
            guard page.pageInfo.hasNextPage else { break }
            guard let cursor = page.pageInfo.endCursor, seen.insert(cursor).inserted else {
                snapshot.isComplete = false; break
            }
            let (next, issues): (CICommitData, [String]) = try await performGraphQLResult(
                query: Self.ciContextsQuery, variables: CIPageVariables(id: applicable.id, after: cursor))
            guard let commit = next.node, commit.oid == applicable.oid,
                  let nextPage = commit.statusCheckRollup?.contexts else { snapshot.isComplete = false; break }
            snapshot.isComplete = snapshot.isComplete && issues.isEmpty
            connection = nextPage
        }
        // Multiple attempts can share a name. Keep the latest result per provider/name.
        var latest: [String: CIContext] = [:]
        for context in contexts {
            if let previous = latest[context.groupKey], previous.orderDate > context.orderDate { continue }
            latest[context.groupKey] = context
        }
        snapshot.checks = latest.values.map(\.check).sorted { $0.name < $1.name || ($0.name == $1.name && $0.id < $1.id) }
        let (current, issues): (CIPRData, [String]) = try await performGraphQLResult(query: Self.ciRevisionQuery, variables: variables)
        guard current.node?.state == "OPEN", current.node?.headRefOid == head,
              current.node?.potentialMergeCommit?.oid == pr.potentialMergeCommit?.oid else {
            throw GitHubClientError.obsoleteCI
        }
        snapshot.isComplete = snapshot.isComplete && issues.isEmpty
        if !snapshot.isComplete { snapshot.warning = "Some checks could not be read. Open GitHub to verify all requirements." }
        return snapshot
    }

    private static let contextFields = """
      pageInfo { hasNextPage endCursor }
      nodes {
        __typename
        ... on CheckRun { id name status conclusion detailsUrl startedAt completedAt checkSuite { createdAt app { id } workflowRun { event workflow { name } } } }
        ... on StatusContext { id context state targetUrl createdAt }
      }
    """
    private static var commitFields: String { "id oid statusCheckRollup { contexts(first: 100) { \(contextFields) } }" }
    private static var ciQuery: String { """
    query PRCI($id: ID!) {
      node(id: $id) { ... on PullRequest {
        state headRefOid
        commits(last: 1) { nodes { commit { \(commitFields) } } }
        potentialMergeCommit { \(commitFields) }
      } }
    }
    """ }
    private static let ciRevisionQuery = """
    query PRCIRevision($id: ID!) {
      node(id: $id) { ... on PullRequest { state headRefOid potentialMergeCommit { id oid } } }
    }
    """
    private static var ciContextsQuery: String { """
    query CIContexts($id: ID!, $after: String) {
      node(id: $id) { ... on Commit { id oid statusCheckRollup { contexts(first: 100, after: $after) { \(contextFields) } } } }
    }
    """ }
}

private struct CIIDVariables: Encodable { let id: String }
private struct CIPageVariables: Encodable { let id: String; let after: String }
private struct CIPRData: Decodable {
    struct PR: Decodable {
        struct Commits: Decodable { struct Node: Decodable { let commit: CICommit }; let nodes: [Node]? }
        let state: String?
        let headRefOid: String?
        let commits: Commits?
        let potentialMergeCommit: CICommit?
    }
    let node: PR?
}
private struct CICommitData: Decodable { let node: CICommit? }
private struct CICommit: Decodable {
    struct Rollup: Decodable { let contexts: CIConnection? }
    let id: String
    let oid: String
    let statusCheckRollup: Rollup?
}
private struct CIConnection: Decodable {
    struct Page: Decodable { let hasNextPage: Bool; let endCursor: String? }
    let pageInfo: Page
    let nodes: [CIContext?]
}
private struct CIContext: Decodable {
    struct Suite: Decodable {
        struct App: Decodable { let id: String }
        struct Run: Decodable { struct Workflow: Decodable { let name: String }; let event: String?; let workflow: Workflow? }
        let createdAt: String?
        let app: App?
        let workflowRun: Run?
    }
    let __typename: String
    let id: String
    let name: String?
    let context: String?
    let status: String?
    let conclusion: String?
    let state: String?
    let detailsUrl: String?
    let targetUrl: String?
    let startedAt: String?
    let completedAt: String?
    let createdAt: String?
    let checkSuite: Suite?
    var groupKey: String {
        if __typename == "StatusContext" { return "status:\(context ?? id)" }
        return ["check", checkSuite?.app?.id ?? "", checkSuite?.workflowRun?.workflow?.name ?? "", checkSuite?.workflowRun?.event ?? "", name ?? id].joined(separator: "\u{0}")
    }
    var orderDate: Date {
        (startedAt ?? createdAt ?? checkSuite?.createdAt).flatMap(GitHubAPIClient.parseISODate) ?? .distantPast
    }
    var check: CICheck {
        let value: CICheck.State
        let raw = __typename == "StatusContext" ? state : (status == "COMPLETED" ? conclusion : status)
        switch raw {
        case "SUCCESS": value = .success
        case "FAILURE", "ERROR", "TIMED_OUT", "STARTUP_FAILURE": value = .failure
        case "IN_PROGRESS": value = .running
        case "QUEUED", "PENDING", "REQUESTED", "EXPECTED": value = .queued
        case "WAITING", "ACTION_REQUIRED": value = .actionRequired
        case "CANCELLED": value = .cancelled
        case "SKIPPED": value = .skipped
        case "NEUTRAL": value = .neutral
        default: value = .unknown
        }
        let url = (detailsUrl ?? targetUrl).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        return CICheck(id: id, name: name ?? context ?? "Unknown check", state: value, url: url,
                       startedAt: startedAt.flatMap(GitHubAPIClient.parseISODate), attempt: startedAt ?? createdAt ?? "")
    }
}
