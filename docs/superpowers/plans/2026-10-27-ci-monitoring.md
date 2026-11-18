# CI Monitoring Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans task-by-task with test-driven development.

**Goal:** Surface CI status and deliver opt-in, deduplicated failures for all accessible open authored PRs, with individual mutes.
**Architecture:** Extend authenticated GraphQL reads with paginated commit rollups. A separate account-lifetime-bound monitor discovers authored PRs independently of dashboard filters, stores observations/mutes atomically, and delegates notifications to the existing dispatcher. Shared row UI serves both layouts.
**Tech Stack:** Swift 6.2, SwiftUI/AppKit, GraphQL, XCTest and native UI journeys.
**Spec:** ../specs/2026-10-27-ci-monitoring-design.md

## Global Constraints
- One active account, synthetic tests only; no production installation or Keychain changes.
- Intervals 1/5/15/30 minutes; default 5; monitoring opt-in.
- Unknown/partial CI never implies passing or merge readiness.
- Run window-opening unit and native tests sequentially.

## Review Focus
- New commits and test-merge revision changes cannot leak obsolete failure alerts.
- Pagination failures retain observations without falsely removing monitored PRs.
- Restart, mute/unmute and enable toggles establish correct baselines.
- Account retirement invalidates in-flight reads, writes and notifications.
- Unknown conclusions, rate limits and missing permission remain visible uncertainty.

### Task 1: CI domain and API
**Files:** Domain/CIStatus.swift, Domain/Models.swift, Domain/PullRequestStatusCalculator.swift, Data/GitHubClient.swift, Tests/PRPulseAppTests/CIMonitoringTests.swift, Tests/PRPulseAppTests/GitHubCITests.swift (paths under Sources/PRPulseApp unless Tests).
**Interfaces:** CIStatus carries head/applicable revision, checks, completeness and observation time; GitHubClient.fetchCI(for:) returns CIStatus. Existing clients default to unavailable.
- [x] Write failing aggregation and readiness tests: failed check blocks ready; unknown prevents ready; skipped stays distinct; current revision preserved.
- [x] Run swift test --filter CIMonitoringTests; expect missing-feature failure.
- [x] Implement immutable check models and GraphQL pagination; fetch head and test-merge checks, validate revision before returning; add rate-limit error with retry date.
- [x] Add URLProtocol fixtures covering check/status decoding, pagination, permission failures and revision races; run focused tests to green.

### Task 2: Monitoring and persistence
**Files:** Services/CIMonitor.swift, Data/CIMonitorStore.swift, Services/NotificationDispatcher.swift, Data/GlobalPreferencesStore.swift, Domain/Models.swift, App/DashboardViewModel.swift; matching tests.
**Interfaces:** CIMonitor polls the active GitHubClient, stores per-PR observations/mutes and publishes snapshots; start/stop/change-settings live in dashboard lifecycle. Settings use ciFailureAlerts and ciRefreshInterval.
- [x] Write failing tests for silent baseline, fresh failures, reruns, restart, mute/unmute, closed removal, pagination, stale sessions and incomplete reads.
- [x] Run focused tests; expect feature missing.
- [x] Implement serial polling with backoff and cancellation; atomic storage guarded by account lifetime; grouped failure delivery checks current revision; persist only safe metadata.
- [x] Run focused tests and whole swift test; expect pass.

### Task 3: Shared UI, settings and local verification
**Files:** UI/CIStatusView.swift, UI/PullRequestRowView.swift, UI/ContentView.swift, UI/Settings/GeneralSettingsViews.swift, Tests/E2E fixtures and journeys, README.md and docs/manual-product-qa.md.
**Interfaces:** Shared CI detail popover and My PR mute action consume monitor snapshots; Settings controls bind persisted monitoring preferences and expose permission status.
- [x] Add native fixture journey for failed/running CI, detail links, toggling monitoring, mute persistence and both layouts before implementing UI. Skipped/neutral aggregation is covered by unit fixtures.
- [x] Implement controls and status; correct readiness copy; document awake/running/active-account and coverage limits.
- [x] Run all Swift tests, fixture tests, both layout native journeys, installer regressions and release build; inspect screenshots locally.
- [x] Obtain independent branch review, address material findings with regression tests, and report local result without creating a PR yet.

## Verification record

2026-10-27: 95 unit tests; full 20 native journeys followed by 3 affected journeys on final application code; arm64 and x86_64 release builds; temporary-fixture installer regressions; links and whitespace checks. All passed. See ../../manual-product-qa.md for evidence and limits. Production app and credentials were not changed.
