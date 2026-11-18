# PR Pulse Public Product Roadmap Design

## Delivery status — 2026-10-16

The v0.2.0 feature branch implements multiple GitHub accounts (one active at a time), profile-isolated data, rule-based saved views, loaded-data counts, keyboard shortcuts and one retained native Settings window. See the [changelog](../../../CHANGELOG.md) and [release QA](../../manual-product-qa.md) for scope and verification. These changes are not available in v0.1.5; publication still requires PR review and passing CI.

Automatic updates, Developer ID signing and notarization remain deferred. Manual collections, cloud sync and team sharing are not implemented. The adoption targets below remain goals, not measured outcomes or a guarantee of stars. The experience and milestone sections describe product intent; the implementation now uses an AppKit status item and SwiftUI-hosted popover rather than `MenuBarExtra`.

## Product intent

PR Pulse is a GitHub-only, macOS-only open-source menu-bar app that helps developers see and act on pull requests without living in GitHub notifications. The initial adoption goal is 100 GitHub stars and 25 recurring users.

The product promise is: **know what needs you, defer the rest, and return to focused work.**

## Target users and scope

Primary users are developers and engineering leads who review pull requests several times per week across personal, team, or watched repositories.

The first public product deliberately excludes GitLab, Bitbucket, mobile platforms, team collaboration, hosted accounts, and paid plans. GitHub and macOS remain the sole platform scope until the activation and retention targets below are met.

## North-star experience

1. The menu-bar icon shows a compact badge containing the total number of actionable PRs.
2. The user clicks the icon to open the PR Pulse popover. No workspace tabs are rendered directly in the macOS menu bar.
3. The popover presents default views plus user-created saved views as compact tabs. Each tab carries an actionable count.
4. The user opens a PR, marks it TODO, snoozes it, or marks it not applicable.
5. A refresh recomputes the PR status, workspace membership, tab counts, and the global badge.

An actionable PR is one that is awaiting the user’s review, is authored by the user and has changes requested, or is explicitly marked TODO. Snoozed and not-applicable PRs are excluded from actionable counts.

## Saved views

Saved views are the first user-defined grouping model. They are rule-based and update automatically rather than requiring the user to manually maintain a collection.

Each saved view has:

- A name and stable identifier.
- Repository rules: explicit `owner/repo` selections, with all tracked repositories as the default scope.
- PR-state rules: awaiting my review, changes requested, authored by me, TODO, draft, or any.
- Optional text match over title and repository name.
- A display order and enabled state.

Default views—My PRs, Review Requested, and Watched—remain available and cannot be deleted. Users can create, edit, reorder, disable, and delete saved views in Settings. The popover shows enabled saved views after default views; overflow behavior is specified during the UI implementation so the panel remains compact.

Manual per-PR collections and multi-group pinning are explicitly deferred. They are only reconsidered after feedback shows that rule-based views do not cover recurring workflows.

## Release sequence and acceptance gates

### v0.1.0 — Publicly installable

Outcome: a new macOS user can install PR Pulse, connect GitHub, and see PRs in fewer than five minutes.

Required work:

- Publish a stable semantic GitHub Release; the current prerelease-only state must not be the public install path.
- Correct the README installer source URL to the `master` branch and validate the exact command against GitHub’s `releases/latest` API.
- Provide a DMG and ZIP for the stable release, with an explicit unsigned/notarization statement until Developer ID signing is available.
- Add a macOS CI test job in addition to the artifact build job.
- Add a license, security/privacy statement, contribution guide, issue templates, changelog, and GitHub topics.
- Add a concise onboarding path covering token permissions, Keychain storage, refresh, and recovery from authentication errors.

Exit evidence:

- A clean-machine install test passes using the documented command.
- CI builds and runs the test suite on a supported Xcode runner.
- Five external testers complete setup without a maintainer intervention.

### v0.2.0 — Daily triage workspaces

Outcome: testers use PR Pulse three or more times per week before opening GitHub.

Required work:

- Calculate and render the global actionable badge.
- Persist saved-view definitions locally.
- Evaluate saved-view rules against loaded PR presentations.
- Render enabled saved views as tabs inside the click-open `MenuBarExtra` popover.
- Show a per-view actionable count and clear empty-state behavior.
- Support create, edit, reorder, disable, and delete actions in Settings.
- Add keyboard navigation for tab switching, search, opening a PR, TODO, and snooze actions.

Exit evidence:

- All saved-view persistence and matching tests pass.
- Ten testers can create a workspace and find an actionable PR in it.
- Product feedback shows the workspace model reduces navigation to github.com.

### v0.3.0 — PR health and reliable attention

Outcome: users answer “what needs me now?” from the popover without opening every PR.

Required work:

- Surface check/CI state, review state, mergeability, and staleness in a scannable row.
- Improve rate-limit, network, token, and GraphQL error recovery with clear retry states.
- Ensure notification logic honors user preferences and does not duplicate alerts.
- Add accessibility labels, keyboard coverage, and a manual visual QA checklist.

Exit evidence:

- Testers accurately identify their next action in a scripted triage exercise.
- No unresolved P0/P1 reliability defects remain for two consecutive release candidates.

### v0.4.0 and beyond — Adoption loop

Outcome: achieve 100 GitHub stars and 25 recurring users while maintaining responsive open-source support.

Required work:

- Release a polished demo GIF/video, install instructions, screenshots, and an honest limitations section.
- Run a measured launch through relevant Mac, Swift, GitHub, and independent-developer communities, observing each community’s self-promotion policies.
- Publish a short build story focused on reducing PR-notification overload.
- Convert recurring user requests into public issues with labels and milestone ownership.
- Evaluate an auto-update approach only after stable releases are established.

Exit evidence:

- 100 GitHub stars.
- 25 users active at least weekly, measured from voluntary feedback or opt-in, privacy-preserving telemetry if introduced later.
- A maintained issue backlog and a predictable release-note cadence.

## Quality and operational model

### Required release gates

- Build a universal macOS binary or explicitly label architecture support.
- Run unit tests on macOS with Xcode in CI.
- Perform a clean installation test of the published DMG.
- Validate GitHub token setup with a fine-grained token against public and permitted private repositories.
- Test missing token, revoked token, API failure, rate limit, no PRs, and no watched repositories.
- Verify the menu-bar badge, saved-view counts, snooze exclusion, notification preferences, and Keychain behavior.
- Publish release notes that identify new features, known limitations, and upgrade guidance.

### Backlog policy

Every issue must carry a type (`bug`, `feature`, `documentation`, `maintenance`), priority (`P0` through `P3`), and target milestone. P0 blocks a release; P1 is fixed in the next planned release; P2 is scheduled only after evidence; P3 remains an idea.

Features are prioritized by: user frequency, impact on the north-star loop, confidence from feedback, and effort. A feature cannot enter an active milestone without an explicit user problem, acceptance criteria, test plan, and owner.

### Cadence

- Weekly: triage issues, reply to feedback, update milestone status, and publish a small status note when a release is in progress.
- Every release: review activation failures, install failures, crashes/errors, and the most-requested workflow gap.
- Monthly: evaluate activation, weekly usage feedback, saved-view usage, actionable-PR click-through, issue response time, release cadence, and star growth. Re-rank the roadmap based on this evidence.

## Metrics

| Area | Metric | Initial target |
| --- | --- | --- |
| Installation | Successful clean install and GitHub connection | 5/5 tester attempts |
| Activation | User sees an actionable PR within five minutes | 80% of testers |
| Retention | Testers using the app at least three times weekly | 60% of testers |
| Workspace value | Testers creating and revisiting a saved view | 50% of testers |
| Reliability | P0/P1 bugs open at release | 0 |
| Community | GitHub stars | 100 |
| Support | First response to a public issue | under 72 hours |

## Testing strategy

Unit tests cover actionable-status calculation, saved-view rule evaluation, tab counts, persistence migrations, sorting, and snooze behavior. API client tests use fixture responses to exercise GraphQL decoding, pagination, partial failures, and rate-limit handling. Integration tests exercise refresh-to-presentation state using a mock GitHub client and a temporary store. Manual QA verifies the `MenuBarExtra` popover, badge updates, Settings flows, notifications, accessibility, and DMG installation.

## Risks and decisions

- **Release trust:** Until Developer ID signing and notarization are available, the installer must explain the Gatekeeper step clearly. Signing is a high-priority product investment, not a hidden limitation.
- **GitHub API limits:** Refresh frequency, pagination, per-repository queries, and retry behavior must respect rate-limit responses and avoid background churn.
- **Scope creep:** Cross-platform providers, manual collections, and advanced automation stay out of v0.2.0.
- **Privacy:** Tokens remain in Keychain. No usage telemetry is added without explicit disclosure and opt-in.

## Out of scope for the first public roadmap

- GitLab, Bitbucket, Jira, Slack, and team-shared queues.
- In-app PR approval, comments, or diff review.
- Cloud sync of settings or saved views.
- Billing, user accounts, and subscriptions.
