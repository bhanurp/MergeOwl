# Remaining Product Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute inline; no delegation without separate authorization.

**Goal:** Complete reliable Settings, isolated multiple GitHub accounts, and account-specific saved PR views without auto-updates.

**Architecture:** Deliver in three independently testable phases: Settings ownership, account sessions, saved views. One retained AppKit delegate owns windows; an observable account coordinator owns replaceable, isolated dashboard sessions. Saved-view membership is derived from each account's deduplicated loaded PRs.

**Tech Stack:** Swift 6.2, macOS 14+, SwiftUI hosted by AppKit, Foundation, Security/Keychain, XCTest/XCUITest and existing GitHub fixtures. No new dependencies.

**Spec:** ../specs/2026-10-15-remaining-product-features-design.md

**Account spec:** ../specs/2026-10-11-multiple-github-accounts-design.md

## Global Constraints

- GitHub.com and macOS 14+ only; one active account at a time.
- Keep updater PR #11/worktree untouched; do not merge Sparkle or updater UI.
- Per-account tokens, watched repositories, overrides, snoozes, ledger, activity and saved views; app-wide refresh/notification preferences.
- Existing service identifier and legacy github-token item must remain available for safe migration. Profile account attributes are github-profile:<local-profile-ID>.
- No destructive migration, production token access in tests, telemetry or automatic production deployment. After design approval, the user explicitly authorized feature-branch publication, PR review/comment fixes, merge and a new release once verification gates pass.
- Build/test a separate local app before proposing PRs. Maintain the current installed app unless deployment is explicitly requested.

## Review Focus

1. Old A responses completing after A→B→A: reject retired session results, including side effects (Task 3).
2. Locked Keychain/corrupt legacy data during migration: preserve original files/token and allow retry (Task 2).
3. Identical PRs in multiple source lists/views: deduplicate badges and membership (Task 4).
4. Repeated Settings reopening with production display name: exactly one window, app remains running after close (Task 1).
5. Deleted/disabled saved selection or inactive-account edits: safe fallback, no cross-account writes (Tasks 3 and 5).

## Phase A — Settings ownership

### Task 1: One retained preferences window

**Files:** Sources/PRPulseApp/App/PRPulseApp.swift, PRPulseApplicationDelegate.swift, SettingsPresenter.swift; UI/ContentView.swift; Tests/PRPulseAppTests/SettingsSceneTests.swift; Tests/E2E/PRPulseUITests.swift and project.yml.

**Interfaces:** PRPulseApplicationDelegate.showSettings() becomes the single main-actor preferences route. PRPulseApp.main() creates NSApplication.shared, retains the delegate for app.run(), and uses accessory activation policy. Native menu Settings… action and reopen route call showSettings().

- [ ] Add a native journey that launches without a preferences window, opens via gear repeatedly, closes/reopens with Command-comma, activates/reopens the application, and asserts exactly one Settings window and a live status item after close. Run the focused native journey and observe the existing duplicate-window failure.
- [ ] Replace the SwiftUI App/Settings scene with AppKit bootstrap; preserve SwiftUI content through existing NSHostingController. Add native application menu Settings…/Quit actions, leaving normal launch windowless and explicit reopen showing the same preferences window.
- [ ] Remove obsolete openSettings/openWindow fallback routes from ContentView only after all production host actions are supplied. Route connection errors to the existing retained native window. Replace brittle source-text tests about the deleted SwiftUI scene with runtime host/window-routing assertions.
- [ ] Run swift test and bash scripts/test_e2e.sh -only-testing:PRPulseUITests/PRPulseUITests/testSettingsWindowIsSingleton. Expected: green tests, one window with production display-name coverage, no duplicate menu icon. Commit fix: unify native Settings ownership.

## Phase B — Multiple accounts

### Task 2: Profiles, credentials and migration

**Files:** new Domain/AccountProfile.swift, Data/AccountRegistry.swift, Data/AccountMigration.swift, Data/GlobalPreferencesStore.swift; UI/KeychainTokenStore 3.swift; Data/PullRequestStore.swift; Domain/Models.swift; new Tests/PRPulseAppTests/AccountStorageTests.swift and AccountMigrationTests.swift.

**Interfaces:** AccountProfile: Codable/Identifiable/Equatable has id: UUID, githubUserID: String, login: String. AccountRegistry actor init(directory: URL), load() throws -> AccountRegistrySnapshot, save(_ snapshot: AccountRegistrySnapshot) throws; snapshot contains profiles, activeProfileID and migration completion. AccountCredentialStore protocol read(profileID: UUID?) throws -> String?, write(_ token: String, profileID: UUID?) throws, remove(profileID: UUID?) throws; nil addresses the legacy item. GlobalPreferencesStore actor loads/saves AppSettings with watchedRepositories/token excluded from global persistence. AccountMigration.run(identity: VerifiedGitHubIdentity, profileID: UUID) async throws -> AccountProfile.

- [ ] Add failing storage tests for independent two-profile token reads/replacement/removal and unaffected legacy item, registry round trip/active selection, and shared preference isolation. Use injected credentials and temporary directories; any Security integration uses a unique test service, never the production service.
- [ ] Add migration tests: copies repositories/overrides/ledger/activity, preserves originals, completes only after verified copies and credential save, retries after interrupted registry save without duplicating accounts, and leaves malformed originals/locked-Keychain state untouched. Run swift test --filter AccountMigrationTests and observe red.
- [ ] Implement stable per-profile directories and atomic registry writes. Refactor KeychainTokenStore with explicit injectable service/account configuration and throwing read for migration; preserve existing convenience methods for compatibility. Default service remains unchanged. Validate copied JSON before completing migration.
- [ ] Keep deletion target-specific and transactional: tombstone profile removal, remove only its credential/data, retain an actionable visible error on credential deletion failure, and resume interrupted cleanup. Add removal tests, including active-account fallback in saved order and last-account onboarding.
- [ ] Run swift test, all storage/migration tests and installer tests. Expected: original data preserved in every injected failure, no plaintext credentials. Commit feat: persist isolated GitHub account profiles.

### Task 3: Session switching and account management UI

**Files:** new App/AccountSessionCoordinator.swift, UI/AccountSelectorView.swift; App/AppDependencies.swift, DashboardViewModel.swift, PRPulseStatusItemController.swift, PRPulseApplicationDelegate.swift; Services/RefreshScheduler.swift, NotificationDispatcher.swift; UI/ContentView.swift, Settings/AccountSettingsView.swift, SettingsShellView.swift; Data/GitHubClient.swift; new Tests/PRPulseAppTests/AccountSessionTests.swift; E2E GitHub fixture/server tests.

**Interfaces:** VerifiedGitHubIdentity holds id: String and login: String. GitHubAccountValidator.validate(token: String) async throws -> VerifiedGitHubIdentity checks REST identity and GraphQL viewer consistency. @MainActor AccountSessionCoordinator exposes profiles, activeProfileID, dashboard and switchAccount(to: UUID) async, connect(token: String, replacing: UUID?) async throws, removeAccount(id: UUID) async throws. DashboardViewModel.retire() async cancels tasks/stops scheduler, invalidates its session token and clears visible data. Account-bound client token closures capture profile ID, never mutable active selection.

- [ ] Write tests with controllable async clients: A request paused, switch to B, finish A; verify B PRs/badge/digest/error/ledger/notifications unchanged. Repeat A→B→A and test suspended pagination, repository settings writes and quick actions. Run swift test --filter AccountSessionTests, observe red.
- [ ] Track dashboard tasks and session generation. Capture settings snapshots before spawning persistence tasks; check session validity after awaits and before visible mutations or side effects. Fix scheduler cancellation so cancelled sleep cannot run one extra action. Keep old writes bound to old stores and suppress notifications from retired sessions. Bind clients to immutable per-session credential snapshots to avoid repeating Keychain access for every request.
- [ ] Implement verified add/update, identity mismatch rejection, duplicate GitHub ID credential update, persistent selection and migration fallback while offline. Do not recreate timers twice or revalidate during unrelated view renders.
- [ ] Render the account selector above tabs and account-management list in Settings. Editing a profile does not implicitly select it. Keep token entry blank, confirmation for removal, errors near controls and selection available while offline/expired. Inject coordinator observations into both window and status-item content so no stale dashboard remains hosted.
- [ ] Extend fixtures with distinct octocat and hubot identities/PRs, independent tokens, one expired token and isolated E2E storage. Verify add/switch/remove/relaunch, partial access, duplicate addition and long-login labels; rerun existing journeys.
- [ ] Run complete Swift/fixture/native suites, expected green with no cross-account state. Commit feat: add safe active-account switching.

## Phase C — Saved views and grouping

### Task 4: Persist and evaluate saved-view rules

**Files:** new Domain/SavedPRView.swift, Domain/SavedPRViewMatcher.swift, Data/SavedPRViewStore.swift; App/DashboardViewModel.swift; new Tests/PRPulseAppTests/SavedPRViewTests.swift.

**Interfaces:** SavedPRView: Codable/Identifiable/Equatable has id: UUID, name: String, enabled: Bool, repositories: [String], stateRule: SavedPRStateRule and text: String. Array order is display order. SavedPRStateRule cases any, awaitingReview, changesRequested, authored, todo, draft. SavedPRViewMatcher.matches(_ pr: PullRequestPresentation, view: SavedPRView, viewerLogin: String) -> Bool. SavedPRViewStore actor init(directory: URL), load() throws -> [SavedPRView], save(_ views: [SavedPRView]) throws. Dashboard adds savedViews, selectedSavedViewID, saveView(_:), deleteView(id:), moveView(id:offset:) and selectSavedView(id:).

- [ ] Add red tests with literal PR fixtures for every state rule, AND composition, repository case/exact-match, title/repo substring, trimmed names up to 40 characters, duplicates, empty file migration and malformed file preservation. Add dedup/count tests proving shared PRs count once and snoozed/N/A never count actionable.
- [ ] Implement matcher over active-account loaded presentations, preserving existing status semantics and applying popover filters after membership. Store definitions in the profile directory; atomic writes must preserve old state on failure. Invalid selected ID falls back to Review Requested.
- [ ] Implement saved-view refresh over three sources, one-page-per-source pagination and warning aggregation without claiming fully loaded counts. Reuse Task 3 session guards; add paused-source/account-switch test and partial-failure accessible-result test.
- [ ] Run swift test --filter SavedPRViewTests then swift test; expected green rules, counts, storage and session tests. Commit feat: add account-bound saved PR views.

### Task 5: Management, navigation and keyboard use

**Files:** new UI/Settings/SavedViewsSettingsView.swift, UI/SavedViewEditor.swift, UI/PRViewTabStrip.swift; UI/Settings/SettingsPane.swift, SettingsShellView.swift; UI/ContentView.swift, PullRequestRowView.swift; Tests/E2E/PRPulseUITests.swift.

**Interfaces:** SavedViewsSettingsView(coordinator: AccountSessionCoordinator) edits the active profile. SavedViewEditor uses local draft state and onSave/onCancel callbacks; it does not mutate persisted data until save succeeds. PRViewTabStrip renders defaults then enabled saved views with count/selection callbacks.

- [ ] Add failing native journeys: create scoped view, cancel edit unchanged, save edit changes membership, reorder/disable/delete, duplicate/blank/overlong name validation, account isolation and relaunch selection. Check source-label/count visibility for overflow and long names.
- [ ] Implement grouped native Settings controls with visible validation, move up/down buttons, confirmation for delete, and enabled toggle. Keep defaults immutable. Display a horizontal tab strip with accessible buttons/counts and overflow menu, fixed popover width, loaded-data count explanation, clear empty/loading/error states.
- [ ] Add popover-scoped Command-1/2/3, Command-F, Command-R and arrow navigation. Test focused row TODO/snooze controls with keyboard; do not install global hotkeys. Refresh/popover reopening recomputes counts from the active session.
- [ ] Run native E2E including saved views, overflow and keyboard journeys; expected no clipping, data mixing or Settings duplicates. Commit feat: expose saved views and keyboard triage.

### Task 6: Whole-product local validation and documentation

**Files:** README.md, CHANGELOG.md, Tests/E2E/README.md; new docs/manual-product-qa.md.

- [ ] Run swift test, both installer regression scripts, Python fixture tests and full bash scripts/test_e2e.sh. Inspect every failure rather than omitting pre-existing failures. Rebuild a temporary app with separate bundle identity, storage root and Keychain service.
- [ ] Smoke-test native icon/popover/badge, Command-comma/gear/reopen singleton, account switching/relaunch, saved-view management and counts, filters, snooze and partial-access warnings. Record light/dark and keyboard/accessibility checks, and disclose live SSO/notification delivery limits.
- [ ] Update README/changelog to verified functionality only, keeping auto-updates/signing explicitly deferred. Preserve useful setup/security guidance and refresh media only with synthetic data.
- [ ] Self-review the whole diff for lost migration data, cross-session side effects, duplicate timers/windows, count inflation and misleading scope. No independent subagent review unless authorized. Commit docs: document account workspaces and QA results.
- [ ] Report complete vs pending work with exact test evidence. Use the subsequent user authorization to create the PR, resolve CodeRabbit comments, merge only after latest-head checks/review pass, and publish/verify v0.2.0. The installed production app remains untouched.

## Self-review

Each approved requirement maps to a task above. Settings is independently deliverable; accounts depend on storage/migration; saved views depend on active profile identity and session-safe dashboard state. No updater integration is a prerequisite. The five review-focus failure classes each have an explicit regression task. External Apple credentials are not needed for this implementation.
