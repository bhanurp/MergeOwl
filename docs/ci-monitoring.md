# MergeOwl CI monitoring

These controls are included from v0.2.2 onward. They are not included in v0.2.1 or earlier downloads. Existing README screenshots show earlier releases.

## See checks

In either **Tabbed** or **Compact**, click the CI status below a PR title. The detail popover lists check names and outcomes, running time when supplied by GitHub, the applicable revision, last successful observation, and links to the checks. You can copy an individual check link.

The app distinguishes failed, running, queued, cancelled, action-required, skipped/neutral, unavailable and no-checks-reported states. A skipped check is not a successfully executed test. CI status appears in all three PR lists. Passing checks alone do not establish merge readiness: approvals, conflicts, required checks, branch rules and other GitHub requirements still apply. **No known blockers** is not a guarantee that GitHub will allow a merge.

CI labels describe the last fetched snapshot, not a live stream from GitHub. Each row shows when checks were observed. Opening the popover refreshes the selected view when its visible CI snapshots are older than 30 seconds; rapid reopen attempts are coalesced. During a list refresh the row says **Checking CI…**, and the previous details remain available. Manual refresh remains available at any time. This does not change the separate failure-alert polling interval.

Failures and CI states needing attention on your authored PRs remain actionable in the badge and **Actionable** filter, unless you snooze or mark the PR not relevant. A failure on someone else's PR does not by itself assign an action to you.

GitHub's test-merge checks take precedence when present. Results from a PR that changes during the read are discarded; other PRs continue loading. Failed refreshes retain previous check details with a stale/unavailable indication, rather than treating a network error as a CI failure.

## Enable failure alerts

1. Open **More → Settings → Notifications**.
2. Enable **CI failure alerts for My PRs** and allow macOS notifications when requested.
3. Select **Check CI every**: 1, 5, 15 or 30 minutes. The default is 5 minutes, separate from dashboard refresh.
4. Check the monitoring message, last/next check times and notification permission status in the same pane.

The interval schedules discovery; it does not guarantee every check can be refreshed on each pass. CI reads, pagination and failure revalidation share a request allowance of 30 requests per minute and 1,800 per rolling hour, with at least 500 reported GitHub quota points reserved for other activity. Discovery enrichment can use at most 20 of those requests per minute, leaving capacity for live failure verification. When this allowance is exhausted, dashboard discovery continues, CI coverage is marked incomplete and previous results remain stale. Within each page, PRs without a recent successful CI refresh are checked first. GitHub may impose additional limits.

This discovers accessible open PRs authored by the **active account**, including additional pages. It does not depend on the displayed tab, saved view, search, filters or watched repositories. Switching accounts stops the old session's monitor. It does not monitor inactive accounts.

The first observation when enabling alerts or discovering a PR establishes a silent baseline. Subsequent newly observed failures produce one grouped notification per PR in that polling pass. Reruns can produce new alerts; repeated polls of the same failure do not. Observation records survive relaunch. Quiet hours suppress delivery without replaying missed alerts later. Closed/merged PRs stop being monitored after complete discovery.

## Mute one PR

For a PR you authored, open **More PR actions (…) → Mute CI failure alerts**. The row shows **CI alerts muted**. Mutes are account-specific and survive restart. Choose **Unmute CI failure alerts** to resume; the next observation becomes a silent baseline. Muting does not hide check results or alter GitHub.

## Availability and limits

- The app must be running and the Mac awake. Closing the popover is fine; quitting the app stops monitoring. Polling is not immediate push delivery, and sleep/network delays can extend the interval.
- Token permissions, organization SSO, GitHub search limits and rate limits can limit coverage. A valid account connection does not guarantee access to checks. The monitor reports incomplete coverage and backs off after rate-limit responses. GitHub search returns at most 1,000 results; the app does not claim exhaustive coverage beyond that limit.
- My PRs and Reviews report search limits separately from token-access warnings. Only authored-PR discovery affects the failure monitor's coverage status. Watched keeps its documented latest-loaded subset instead of showing a search-cap warning.
- A fine-grained token may need repository **Checks: read** and **Commit statuses: read** in addition to existing repository/PR access. Follow your organization's policy; never grant write access just to view CI. [GitHub's fine-grained permission reference](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens) describes endpoint permissions.
- If macOS notifications are disabled, use **Open macOS notification settings**. The CI display still works without OS alerts.
- No workflow reruns, approvals or merges are performed. No private CI logs are uploaded or summarized.
- Fixture tests verify application behavior with synthetic data. They do not prove live organization SSO, actual provider behavior or macOS notification delivery.
