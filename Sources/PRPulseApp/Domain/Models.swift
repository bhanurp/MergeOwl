import Foundation

// MARK: - Core pull request models

struct PullRequest: Identifiable, Codable, Equatable, Hashable {
    struct Repository: Codable, Equatable, Hashable {
        var nameWithOwner: String
    }

    struct Author: Codable, Equatable, Hashable {
        var login: String
    }

    var id: String
    var number: Int
    var title: String
    var url: URL
    var repository: Repository
    var author: Author
    var createdAt: Date
    var updatedAt: Date
    var isDraft: Bool
    var detail: PullRequestDetail
    var override: PullRequestOverride

    init(
        id: String,
        number: Int,
        title: String,
        url: URL,
        repository: Repository,
        author: Author,
        createdAt: Date,
        updatedAt: Date,
        isDraft: Bool,
        detail: PullRequestDetail = PullRequestDetail(),
        override: PullRequestOverride = PullRequestOverride()
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.url = url
        self.repository = repository
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDraft = isDraft
        self.detail = detail
        self.override = override
    }
}

struct PullRequestDetail: Codable, Equatable, Hashable {
    enum LinkedReferenceType: String, Codable {
        case issue
        case pullRequest
    }

    struct LinkedReference: Codable, Equatable, Hashable, Identifiable {
        var type: LinkedReferenceType
        var repositoryNameWithOwner: String
        var number: Int
        var url: URL?

        var id: String {
            "\(type.rawValue):\(repositoryNameWithOwner)#\(number)"
        }
    }

    enum MergeableState: String, Codable {
        case mergeable = "MERGEABLE"
        case conflicting = "CONFLICTING"
        case unknown = "UNKNOWN"
    }

    enum ReviewDecision: String, Codable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case reviewRequired = "REVIEW_REQUIRED"
        case commented = "COMMENTED"
    }

    struct Review: Codable, Equatable, Hashable, Identifiable {
        enum State: String, Codable {
            case approved = "APPROVED"
            case changesRequested = "CHANGES_REQUESTED"
            case commented = "COMMENTED"
            case dismissed = "DISMISSED"
        }

        var id: UUID = UUID()
        var reviewer: String
        var state: State
        var submittedAt: Date
    }

    var mergeable: MergeableState
    var reviewDecision: ReviewDecision?
    var latestCommitAt: Date?
    var reviews: [Review]
    var linkedReferences: [LinkedReference]

    init(
        mergeable: MergeableState = .unknown,
        reviewDecision: ReviewDecision? = nil,
        latestCommitAt: Date? = nil,
        reviews: [Review] = [],
        linkedReferences: [LinkedReference] = []
    ) {
        self.mergeable = mergeable
        self.reviewDecision = reviewDecision
        self.latestCommitAt = latestCommitAt
        self.reviews = reviews
        self.linkedReferences = linkedReferences
    }
}

struct PullRequestOverride: Codable, Equatable, Hashable {
    enum State: String, Codable {
        case none
        case todo
        case notApplicable
    }

    var state: State
    var snoozedUntil: Date?

    var isSnoozed: Bool {
        if let snoozedUntil, snoozedUntil > Date() {
            return true
        }
        return false
    }

    init(state: State = .none, snoozedUntil: Date? = nil) {
        self.state = state
        self.snoozedUntil = snoozedUntil
    }
}

struct PullRequestPage: Codable {
    var items: [PullRequest]
    var cursor: String?
    var hasNextPage: Bool
    var warnings: [String] = []
}

enum PullRequestTab: String, CaseIterable, Identifiable, Codable {
    case mine = "My PRs"
    case reviewRequested = "Review Requested"
    case watched = "Watched"

    var id: String { rawValue }

    var queryString: String {
        switch self {
        case .mine:
            return "is:pr is:open author:@me"
        case .reviewRequested:
            return "is:pr is:open review-requested:@me"
        case .watched:
            return "is:pr is:open" // refined by repo list inside data layer
        }
    }
}

// MARK: - Filtering and presentation

struct FilterState: Equatable {
    var searchText: String = ""
    var actionableOnly: Bool = false
    var hideReviewed: Bool = false
    var hideSnoozed: Bool = false
    var hideNotApplicable: Bool = false
}

struct PullRequestStatus: Equatable {
    enum ReviewBadge: Equatable {
        case none
        case reviewed
        case needsReReview
    }

    enum MergeReadiness: Equatable {
        case ready
        case pending
        case blocked(reason: String)
        case checking
    }

    var badge: ReviewBadge
    var approvals: Int
    var changesRequested: Int
    var readiness: MergeReadiness
    var isActionable: Bool
}

struct DigestSnapshot: Equatable {
    var openedCount: Int
    var reviewedCount: Int
    var timeframeDescription: String
}

enum ActivityEventType: String, Codable {
    case openedMyPR
    case reviewedPR
}

struct ActivityEvent: Codable, Equatable {
    var type: ActivityEventType
    var date: Date
}

enum DigestCadence: String, CaseIterable, Identifiable, Codable, Hashable {
    case off
    case weekly
    case biWeekly

    var id: String { rawValue }
}

struct RepositorySubscription: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var nameWithOwner: String
    var notificationsEnabled: Bool
}

struct QuietHours: Codable, Equatable {
    var startHour: Int
    var endHour: Int
}

struct AppSettings: Codable, Equatable {
    var token: String // Deprecated: not persisted; token is stored in Keychain
    var refreshInterval: TimeInterval
    var refreshOnLaunch: Bool
    var notifyNeedsReview: Bool
    var notifyNewReviewRequests: Bool
    var quietHours: QuietHours?
    var snoozeDefaultHour: Int
    var digestCadence: DigestCadence
    var watchedRepositories: [RepositorySubscription]

    static var `default`: AppSettings {
        AppSettings(
            token: "",
            refreshInterval: 5 * 60,
            refreshOnLaunch: true,
            notifyNeedsReview: true,
            notifyNewReviewRequests: true,
            quietHours: nil,
            snoozeDefaultHour: 9,
            digestCadence: .weekly,
            watchedRepositories: []
        )
    }
}
