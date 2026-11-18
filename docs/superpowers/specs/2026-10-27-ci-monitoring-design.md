# CI monitoring

## Intent and scope

Show trustworthy CI information in both popover layouts and notify authors when a newly observed CI attempt fails. The user selected CI monitoring as the first increment, approved automatic monitoring of all open authored PRs when failure alerts are enabled, and requested individual PR mutes. Handoff ownership is a later increment.

## Approach

Recommended: poll GitHub from the running macOS app, using the active account's existing authenticated session and account lifetime guards. This preserves the one-active-account model. A hosted webhook service would add hosting, account installation and credential responsibilities; it is outside this increment. A separate background daemon would add installation and lifecycle complexity; it is also outside scope.

## Proposed product behavior

- CI summaries appear on PRs in My PRs, Reviews and Watched, in both layouts. A detail view lists check names, states and links to GitHub.
- Failure alerts are opt-in and apply only to open PRs authored by the active account. Discover all accessible authored PRs using pagination, independently of visible tabs, filters, saved views and watched repositories. Disclose incomplete discovery rather than claiming complete coverage.
- Proposed interval choices: 1, 5, 15 and 30 minutes, default 5 minutes. This setting is separate from dashboard refresh.
- A My PRs row action mutes or unmutes failure alerts for that PR. Persist mutes and observation state by account, repository and PR identity. Muting does not hide CI status. Unmuting establishes a fresh baseline without replaying failures.
- Enabling alerts establishes a baseline without notifying about existing failures. Later newly observed failures produce one grouped notification per PR per polling observation. Persist deduplication across restart; distinguish reruns using check identity and attempt information where available.
- Only failures applicable to the current PR revision may notify. Revalidate revision and account lifetime before delivery. Do not treat transient fetch failures as CI failures.
- Stop monitoring closed or merged PRs. Switching accounts cancels previous-account polling and pending work. Inactive accounts are not monitored.
- Polling continues with the popover closed while the app runs. Sleep pauses execution; resume performs one refresh rather than replaying missed intervals. Prevent overlapping polls and honor GitHub backoff/rate limits.
- Show last successful check, monitoring state and permission or rate-limit warnings. Retain stale results with a stale label when requests fail.
- Request macOS notification permission when enabling alerts. Explain disabled OS notifications and provide a route to system settings; do not silently claim alerts are deliverable.

## CI correctness

Support GitHub checks and commit statuses, including queued, running, passed, failed, cancelled, action required, no checks reported, and unavailable. Distinguish skipped/neutral outcomes from a successful executed test. Preserve unknown conclusions safely.

Use GitHub's applicable PR check context, including test-merge results when applicable, rather than mixing unrelated revisions. Handle pagination and partial visibility explicitly. Missing required checks must not be shown as passing; only make required-check claims where the API provides enough evidence.

Current merge readiness ignores CI. A failed or pending applicable check must prevent a reassuring ready label. Passing CI alone must not imply all branch rules or merge requirements are satisfied. Unknown or incomplete requirements must remain visibly uncertain.

## Boundaries

No workflow rerun, merge, approval, reviewer ping, hosted service, private log upload, background monitoring of inactive accounts, automatic update work, or production credential/installation changes. Recovery notifications, review handoffs and unusually-long-run alerts are later increments.

## Verification

Use synthetic isolated data and credentials. Test status aggregation, current/test-merge revisions, pagination and missing permissions; baseline and restart deduplication; failures after reruns; grouped delivery; mute/unmute; discovery independent of filters; closed PR removal; account switches and stale asynchronous responses; backoff and non-overlapping timers; settings migration; both layouts and check links. Run unit and native journeys sequentially when they open windows. Run appropriate installer/build regressions before creating a PR. No claim that fixtures prove live GitHub or OS delivery.

## Decisions proposed by the builder

Active-account-only monitoring; a five-minute default; separate CI interval; silent initial baseline and unmute baseline; no historical replay after sleep. These supplement the user's explicit all-open-authored-PR and per-PR-mute requirements.
