import Foundation

protocol GitHubClient {
    nonisolated(nonsending) func fetchViewer() async throws -> String
    nonisolated(nonsending) func fetchPullRequests(tab: PullRequestTab, cursor: String?) async throws -> PullRequestPage
    nonisolated(nonsending) func fetchCI(for pullRequest: PullRequest) async throws -> CIStatus
}

extension GitHubClient {
    nonisolated(nonsending) func fetchCI(for pullRequest: PullRequest) async throws -> CIStatus { .unavailable }
}

enum GitHubClientError: LocalizedError {
    case missingToken
    case invalidResponse
    case invalidDate(String)
    case graphQLErrors([String])
    case apiFailure(String)
    case rateLimited(Date)
    case obsoleteCI

    var isAccessRestriction: Bool {
        let messages: [String]
        switch self {
        case .graphQLErrors(let values): messages = values
        case .apiFailure(let value): messages = [value]
        default: return false
        }
        return !messages.isEmpty && messages.allSatisfy { message in
            let text = message.lowercased()
            return text.contains("saml") || text.contains("resource not accessible") || text.contains("sso")
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "GitHub token missing. Save a token in Settings first."
        case .invalidResponse:
            return "GitHub API returned an invalid response."
        case .invalidDate(let value):
            return "GitHub API returned an invalid date: \(value)"
        case .graphQLErrors(let messages):
            return messages.joined(separator: "\n")
        case .apiFailure(let message):
            return message
        case .rateLimited(let until):
            return "GitHub rate limit reached. Retrying after \(until.formatted(date: .omitted, time: .shortened))."
        case .obsoleteCI:
            return "The PR changed while checking CI. Results will be refreshed."
        }
    }
}

struct GitHubAPIClient: GitHubClient {
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?
    private let watchedRepositoriesProvider: @Sendable () async -> [RepositorySubscription]
    private let requestGate = GitHubRequestGate()

    init(
        session: URLSession = .shared,
        tokenProvider: @escaping @Sendable () -> String? = { KeychainTokenStore().getToken() },
        watchedRepositoriesProvider: @escaping @Sendable () async -> [RepositorySubscription] = { [] }
    ) {
        self.session = session
        self.tokenProvider = tokenProvider
        self.watchedRepositoriesProvider = watchedRepositoriesProvider
    }

    nonisolated(nonsending) func fetchViewer() async throws -> String {
        let data: ViewerData = try await performGraphQL(query: Self.viewerQuery, variables: EmptyVariables())
        return data.viewer.login
    }

    nonisolated(nonsending) func fetchPullRequests(tab: PullRequestTab, cursor: String?) async throws -> PullRequestPage {
        var page: PullRequestPage
        switch tab {
        case .mine, .reviewRequested:
            let query = Self.searchQuery(for: tab)
            page = try await fetchSearchPage(query: query, cursor: cursor)
        case .watched:
            page = try await fetchWatchedPage(cursor: cursor)
        }

        guard !page.items.isEmpty else {
            return page
        }

        let (detailByID, detailWarnings) = try await fetchDetails(ids: page.items.map(\.id))
        page.warnings.append(contentsOf: detailWarnings)
        var enriched: [PullRequest] = []
        for item in page.items {
            var copy = item
            if let detail = detailByID[item.id] {
                copy.detail = detail
            }
            do { copy.detail.ci = try await fetchCI(for: copy) }
            catch {
                if error is CancellationError { throw error }
                if case GitHubClientError.rateLimited = error { throw error }
                var ci = CIStatus.unavailable
                ci.warning = "Check access could not be verified. Open GitHub for details."
                copy.detail.ci = ci
            }
            enriched.append(copy)
        }
        return PullRequestPage(items: enriched, cursor: page.cursor, hasNextPage: page.hasNextPage, warnings: page.warnings)
    }

    private func fetchSearchPage(query: String, cursor: String?) async throws -> PullRequestPage {
        let variables = SearchVariables(query: query, after: cursor)
        let (data, warnings): (SearchData, [String]) = try await performGraphQLResult(query: Self.searchPullRequestsQuery, variables: variables)

        let items = data.search.nodes.compactMap { node -> PullRequest? in
            guard let node,
                  let id = node.id,
                  let number = node.number,
                  let title = node.title,
                  let urlString = node.url,
                  let url = URL(string: urlString),
                  let createdAtRaw = node.createdAt,
                  let updatedAtRaw = node.updatedAt,
                  let createdAt = Self.parseISODate(createdAtRaw),
                  let updatedAt = Self.parseISODate(updatedAtRaw),
                  let repository = node.repository?.nameWithOwner else {
                return nil
            }

            let author = node.author?.login ?? "unknown"
            return PullRequest(
                id: id,
                number: number,
                title: title,
                url: url,
                repository: .init(nameWithOwner: repository),
                author: .init(login: author),
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDraft: node.isDraft ?? false
            )
        }

        var coverageWarnings = warnings
        if (data.search.issueCount ?? 0) > 1000 { coverageWarnings.append("GitHub search limits results to 1,000 PRs; monitoring coverage is incomplete.") }
        return PullRequestPage(
            items: items,
            cursor: data.search.pageInfo.endCursor,
            hasNextPage: data.search.pageInfo.hasNextPage,
            warnings: coverageWarnings
        )
    }

    private func fetchWatchedPage(cursor: String?) async throws -> PullRequestPage {
        // Keep pagination simple for watched repos: merge the latest page from each watched repo.
        guard cursor == nil else {
            return PullRequestPage(items: [], cursor: nil, hasNextPage: false)
        }

        let watchedRepos = await watchedRepositoriesProvider()
            .map(\.nameWithOwner)
            .filter { !$0.isEmpty }

        guard !watchedRepos.isEmpty else {
            return PullRequestPage(items: [], cursor: nil, hasNextPage: false)
        }

        var merged: [PullRequest] = []
        var warnings: [String] = []
        for repo in Set(watchedRepos) {
            let query = "repo:\(repo) is:pr is:open sort:updated-desc"
            let page = try await fetchSearchPage(query: query, cursor: nil)
            merged.append(contentsOf: page.items)
            warnings.append(contentsOf: page.warnings)
        }

        var deduped: [String: PullRequest] = [:]
        for item in merged {
            if let existing = deduped[item.id] {
                deduped[item.id] = (item.updatedAt > existing.updatedAt) ? item : existing
            } else {
                deduped[item.id] = item
            }
        }

        let top = deduped.values
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .prefix(20)

        return PullRequestPage(items: Array(top), cursor: nil, hasNextPage: false, warnings: warnings)
    }

    private func fetchDetails(ids: [String]) async throws -> ([String: PullRequestDetail], [String]) {
        guard !ids.isEmpty else { return ([:], []) }

        let variables = DetailVariables(ids: ids)
        let (data, warnings): (DetailData, [String]) = try await performGraphQLResult(query: Self.pullRequestDetailsQuery, variables: variables)

        var detailByID: [String: PullRequestDetail] = [:]
        for node in data.nodes {
            guard let node, let id = node.id else { continue }

            let mergeable = PullRequestDetail.MergeableState(rawValue: node.mergeable ?? "UNKNOWN") ?? .unknown
            let reviewDecision: PullRequestDetail.ReviewDecision? = {
                guard let raw = node.reviewDecision else { return nil }
                return PullRequestDetail.ReviewDecision(rawValue: raw)
            }()
            let latestCommitAt = node.commits?.nodes.last?.commit?.committedDate.flatMap(Self.parseISODate)

            let reviews: [PullRequestDetail.Review] = (node.reviews?.nodes ?? []).compactMap { rawReview in
                guard let rawReview,
                      let reviewer = rawReview.author?.login,
                      let submittedRaw = rawReview.submittedAt,
                      let submittedAt = Self.parseISODate(submittedRaw),
                      let state = Self.mapReviewState(rawReview.state) else {
                    return nil
                }
                return PullRequestDetail.Review(reviewer: reviewer, state: state, submittedAt: submittedAt)
            }

            var linkedRefs: [PullRequestDetail.LinkedReference] = []

            for issue in node.closingIssuesReferences?.nodes ?? [] {
                guard let issue,
                      let number = issue.number,
                      let repo = issue.repository?.nameWithOwner else { continue }
                linkedRefs.append(
                    PullRequestDetail.LinkedReference(
                        type: .issue,
                        repositoryNameWithOwner: repo,
                        number: number,
                        url: issue.url.flatMap(URL.init(string:))
                    )
                )
            }

            for crossRef in node.timelineItems?.nodes ?? [] {
                guard let source = crossRef?.source,
                      let typeName = source.typeName,
                      let number = source.number,
                      let repo = source.repository?.nameWithOwner else { continue }

                let type: PullRequestDetail.LinkedReferenceType
                switch typeName {
                case "Issue":
                    type = .issue
                case "PullRequest":
                    type = .pullRequest
                default:
                    continue
                }

                linkedRefs.append(
                    PullRequestDetail.LinkedReference(
                        type: type,
                        repositoryNameWithOwner: repo,
                        number: number,
                        url: source.url.flatMap(URL.init(string:))
                    )
                )
            }

            var deduped: [String: PullRequestDetail.LinkedReference] = [:]
            for ref in linkedRefs {
                deduped[ref.id] = ref
            }
            let sortedLinkedRefs = deduped.values.sorted { lhs, rhs in
                if lhs.type != rhs.type {
                    return lhs.type.rawValue < rhs.type.rawValue
                }
                if lhs.repositoryNameWithOwner != rhs.repositoryNameWithOwner {
                    return lhs.repositoryNameWithOwner < rhs.repositoryNameWithOwner
                }
                return lhs.number < rhs.number
            }

            detailByID[id] = PullRequestDetail(
                mergeable: mergeable,
                reviewDecision: reviewDecision,
                latestCommitAt: latestCommitAt,
                reviews: reviews,
                linkedReferences: sortedLinkedRefs
            )
            detailByID[id]?.mergeStateStatus = node.mergeStateStatus
        }

        return (detailByID, warnings)
    }

    private func performGraphQL<Variables: Encodable, DataType: Decodable>(
        query: String,
        variables: Variables
    ) async throws -> DataType {
        let (data, _): (DataType, [String]) = try await performGraphQLResult(query: query, variables: variables)
        return data
    }

    func performGraphQLResult<Variables: Encodable, DataType: Decodable>(
        query: String,
        variables: Variables
    ) async throws -> (DataType, [String]) {
        try Task.checkCancellation()
        try await requestGate.check()
        guard let token = tokenProvider(), !token.isEmpty else {
            throw GitHubClientError.missingToken
        }

        var request = URLRequest(url: Self.graphQLEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try Self.encoder.encode(GraphQLRequest(query: query, variables: variables))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubClientError.invalidResponse
        }
        if http.statusCode == 429 || (http.statusCode == 403 && (http.value(forHTTPHeaderField: "Retry-After") != nil || http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0")) {
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init).map { Date().addingTimeInterval(max(60, $0)) }
            let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
            let until = max(Date().addingTimeInterval(60), retry ?? reset ?? Date().addingTimeInterval(300))
            await requestGate.deferUntil(until)
            throw GitHubClientError.rateLimited(until)
        }

        guard (200...299).contains(http.statusCode) else {
            let failure = try? Self.decoder.decode(APIFailure.self, from: data)
            throw GitHubClientError.apiFailure(failure?.message ?? "GitHub API error \(http.statusCode)")
        }

        let decoded = try Self.decoder.decode(GraphQLResponse<DataType>.self, from: data)
        if decoded.errors?.contains(where: { $0.type == "RATE_LIMITED" }) == true {
            let until = Date().addingTimeInterval(300)
            await requestGate.deferUntil(until)
            throw GitHubClientError.rateLimited(until)
        }
        if let errors = decoded.errors, !errors.isEmpty, decoded.data == nil {
            throw GitHubClientError.graphQLErrors(errors.map(\.message))
        }

        guard let payload = decoded.data else {
            throw GitHubClientError.invalidResponse
        }
        return (payload, Array(Set(decoded.errors?.map(\.message) ?? [])).sorted())
    }

    private static func searchQuery(for tab: PullRequestTab) -> String {
        switch tab {
        case .mine:
            return "is:pr is:open author:@me sort:updated-desc"
        case .reviewRequested:
            return "is:pr is:open review-requested:@me sort:updated-desc"
        case .watched:
            return "is:pr is:open sort:updated-desc"
        }
    }

    static func parseISODate(_ raw: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = withFractional.date(from: raw) {
            return value
        }

        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime]
        return withoutFractional.date(from: raw)
    }

    private static func mapReviewState(_ raw: String?) -> PullRequestDetail.Review.State? {
        guard let raw else { return nil }
        switch raw {
        case PullRequestDetail.Review.State.approved.rawValue:
            return .approved
        case PullRequestDetail.Review.State.changesRequested.rawValue:
            return .changesRequested
        case PullRequestDetail.Review.State.dismissed.rawValue:
            return .dismissed
        case PullRequestDetail.Review.State.commented.rawValue:
            return .commented
        default:
            return nil
        }
    }

    static func apiURL(_ path: String) -> URL {
        #if E2E_TESTING
        let base = ProcessInfo.processInfo.environment["PRPULSE_E2E_API_URL"]!
        return URL(string: base)!.appendingPathComponent(path)
        #else
        return URL(string: "https://api.github.com")!.appendingPathComponent(path)
        #endif
    }

    private static var graphQLEndpoint: URL { apiURL("graphql") }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static let viewerQuery = """
    query Viewer {
      viewer { login }
    }
    """

    private static let searchPullRequestsQuery = """
    query SearchPRs($query: String!, $after: String) {
      search(query: $query, type: ISSUE, first: 20, after: $after) {
        issueCount
        pageInfo { hasNextPage endCursor }
        nodes {
          ... on PullRequest {
            id
            number
            title
            url
            createdAt
            updatedAt
            isDraft
            author { login }
            repository { nameWithOwner }
          }
        }
      }
    }
    """

    private static let pullRequestDetailsQuery = """
    query PRDetails($ids: [ID!]!) {
      nodes(ids: $ids) {
        ... on PullRequest {
          id
          mergeable
          mergeStateStatus
          reviewDecision
          commits(last: 1) {
            nodes { commit { committedDate } }
          }
          reviews(last: 50) {
            nodes {
              author { login }
              state
              submittedAt
            }
          }
          closingIssuesReferences(first: 10) {
            nodes {
              number
              url
              repository { nameWithOwner }
            }
          }
          timelineItems(itemTypes: [CROSS_REFERENCED_EVENT], first: 20) {
            nodes {
              ... on CrossReferencedEvent {
                source {
                  __typename
                  ... on Issue {
                    number
                    url
                    repository { nameWithOwner }
                  }
                  ... on PullRequest {
                    number
                    url
                    repository { nameWithOwner }
                  }
                }
              }
            }
          }
        }
      }
    }
    """
}

private struct EmptyVariables: Encodable {}

private struct GraphQLRequest<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

private struct GraphQLResponse<DataType: Decodable>: Decodable {
    let data: DataType?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    let message: String
    let type: String?
}

private struct APIFailure: Decodable {
    let message: String
}

private struct ViewerData: Decodable {
    struct Viewer: Decodable {
        let login: String
    }
    let viewer: Viewer
}

private struct SearchVariables: Encodable {
    let query: String
    let after: String?
}

private struct SearchData: Decodable {
    struct SearchConnection: Decodable {
        let issueCount: Int?
        struct PageInfo: Decodable {
            let hasNextPage: Bool
            let endCursor: String?
        }

        struct SearchNode: Decodable {
            struct Author: Decodable {
                let login: String?
            }

            struct Repository: Decodable {
                let nameWithOwner: String?
            }

            let id: String?
            let number: Int?
            let title: String?
            let url: String?
            let createdAt: String?
            let updatedAt: String?
            let isDraft: Bool?
            let author: Author?
            let repository: Repository?
        }

        let pageInfo: PageInfo
        let nodes: [SearchNode?]
    }

    let search: SearchConnection
}

private struct DetailVariables: Encodable {
    let ids: [String]
}

private struct DetailData: Decodable {
    struct PullRequestNode: Decodable {
        let mergeStateStatus: String?
        struct Commits: Decodable {
            struct CommitNode: Decodable {
                struct Commit: Decodable {
                    let committedDate: String?
                }
                let commit: Commit?
            }
            let nodes: [CommitNode]
        }

        struct Reviews: Decodable {
            struct ReviewNode: Decodable {
                struct Author: Decodable {
                    let login: String?
                }
                let author: Author?
                let state: String?
                let submittedAt: String?
            }
            let nodes: [ReviewNode?]
        }

        struct ClosingIssuesReferences: Decodable {
            struct IssueNode: Decodable {
                struct Repository: Decodable {
                    let nameWithOwner: String?
                }
                let number: Int?
                let url: String?
                let repository: Repository?
            }
            let nodes: [IssueNode?]
        }

        struct TimelineItems: Decodable {
            struct CrossRefNode: Decodable {
                struct Source: Decodable {
                    struct Repository: Decodable {
                        let nameWithOwner: String?
                    }
                    let typeName: String?
                    let number: Int?
                    let url: String?
                    let repository: Repository?

                    enum CodingKeys: String, CodingKey {
                        case typeName = "__typename"
                        case number
                        case url
                        case repository
                    }
                }
                let source: Source?
            }
            let nodes: [CrossRefNode?]
        }

        let id: String?
        let mergeable: String?
        let reviewDecision: String?
        let commits: Commits?
        let reviews: Reviews?
        let closingIssuesReferences: ClosingIssuesReferences?
        let timelineItems: TimelineItems?
    }

    let nodes: [PullRequestNode?]
}

struct MockGitHubClient: GitHubClient {
    private var currentUser: String
    private var dataset: [PullRequestTab: [PullRequest]]
    private let pageSize = 20

    init(currentUser: String = "octocat") {
        self.currentUser = currentUser
        self.dataset = MockGitHubClient.makeDataset(currentUser: currentUser)
    }

    nonisolated(nonsending) func fetchViewer() async throws -> String {
        currentUser
    }

    nonisolated(nonsending) func fetchPullRequests(tab: PullRequestTab, cursor: String?) async throws -> PullRequestPage {
        let allItems = dataset[tab] ?? []
        let startIndex: Int
        if let cursor, let index = Int(cursor) {
            startIndex = index
        } else {
            startIndex = 0
        }

        let endIndex = min(startIndex + pageSize, allItems.count)
        let items = Array(allItems[startIndex..<endIndex])
        let hasNext = endIndex < allItems.count
        let nextCursor = hasNext ? String(endIndex) : nil

        // simulate latency
        try await Task.sleep(nanoseconds: 150_000_000)

        return PullRequestPage(items: items, cursor: nextCursor, hasNextPage: hasNext)
    }

    private static func makeDataset(currentUser: String) -> [PullRequestTab: [PullRequest]] {
        var mine: [PullRequest] = []
        var reviewRequested: [PullRequest] = []
        var watched: [PullRequest] = []

        for index in 1...35 {
            let isDraft = index % 5 == 0
            let repo = PullRequest.Repository(nameWithOwner: "apple/swift-\(index % 4)")
            let detail = PullRequestDetail(
                mergeable: isDraft ? .unknown : (index % 2 == 0 ? .mergeable : .conflicting),
                reviewDecision: index % 3 == 0 ? .approved : .reviewRequired,
                latestCommitAt: Date().addingTimeInterval(Double(-index * 18_000)),
                reviews: makeReviews(index: index, currentUser: currentUser),
                linkedReferences: makeLinkedReferences(index: index, repository: repo.nameWithOwner)
            )
            let pr = PullRequest(
                id: UUID().uuidString,
                number: 1000 + index,
                title: "Improve reliability of build pipeline \(index)",
                url: URL(string: "https://github.com/\(repo.nameWithOwner)/pull/\(1000 + index)")!,
                repository: repo,
                author: .init(login: index % 2 == 0 ? currentUser : "collaborator\(index)"),
                createdAt: Date().addingTimeInterval(Double(-index * 48_000)),
                updatedAt: Date().addingTimeInterval(Double(-index * 22_000)),
                isDraft: isDraft,
                detail: detail,
                override: PullRequestOverride()
            )

            mine.append(pr)
            if index % 2 == 0 {
                reviewRequested.append(pr)
            }
            if index % 3 == 0 {
                watched.append(pr)
            }
        }

        return [.mine: mine, .reviewRequested: reviewRequested, .watched: watched]
    }

    private static func makeReviews(index: Int, currentUser: String) -> [PullRequestDetail.Review] {
        var reviews: [PullRequestDetail.Review] = []
        let baseDate = Date().addingTimeInterval(TimeInterval(-index * 11_000))
        let reviewers = ["alice", "bob", currentUser, "eve"].shuffled()
        for (offset, reviewer) in reviewers.enumerated() {
            let state: PullRequestDetail.Review.State
            switch (offset + index) % 3 {
            case 0:
                state = .approved
            case 1:
                state = .changesRequested
            default:
                state = .commented
            }
            let review = PullRequestDetail.Review(
                reviewer: reviewer,
                state: state,
                submittedAt: baseDate.addingTimeInterval(TimeInterval(offset * 4_000))
            )
            reviews.append(review)
        }
        return reviews
    }

    private static func makeLinkedReferences(index: Int, repository: String) -> [PullRequestDetail.LinkedReference] {
        var refs: [PullRequestDetail.LinkedReference] = []
        if index % 2 == 0 {
            refs.append(
                PullRequestDetail.LinkedReference(
                    type: .issue,
                    repositoryNameWithOwner: repository,
                    number: 200 + index,
                    url: URL(string: "https://github.com/\(repository)/issues/\(200 + index)")
                )
            )
        }
        if index % 3 == 0 {
            refs.append(
                PullRequestDetail.LinkedReference(
                    type: .pullRequest,
                    repositoryNameWithOwner: repository,
                    number: 300 + index,
                    url: URL(string: "https://github.com/\(repository)/pull/\(300 + index)")
                )
            )
        }
        return refs
    }
}
