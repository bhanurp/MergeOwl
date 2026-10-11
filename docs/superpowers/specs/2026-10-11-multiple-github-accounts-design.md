# Multiple GitHub accounts

## Approved product intent

Users can save multiple GitHub.com accounts and select exactly one account for the entire menu-bar dashboard. Watched repositories, triage marks, and snoozes belong to each account. Refresh and notification preferences remain app-wide. Support macOS 14+ and the existing Swift 6.2 package; do not add third-party dependencies or change supported providers.

## Account identity and credentials

An account profile has an immutable GitHub user ID, current login, and local profile ID. Persist only non-secret profile metadata and the active profile ID. Each profile's token is stored as a separate item in the existing Keychain service. Tokens must never appear in settings files, diagnostics, or logs.

Validate REST identity and GraphQL viewer access before adding an account. Identity disagreement or invalid credentials prevents addition. Re-adding the same GitHub user updates that profile's token instead of making a duplicate. Updating a token to a different GitHub identity must be rejected with an instruction to add a separate account. Token validation alone does not save it.

## User interface

Place an account selector above the existing PR tabs in the popover. Show the selected login and a checkmark beside the active account. An Add account item opens Settings → Account. With no profiles, show Connect GitHub and the existing onboarding empty state. Avoid truncation ambiguity for long logins and provide accessible labels.

Settings → Account lists saved accounts with their login and an active indicator, plus Add account, token update/test, and Remove account controls. Token entry remains blank after saving/reopening. Switching accounts is explicit; merely selecting an account to manage its credentials must not switch the dashboard. Confirm account removal and explain that it removes that profile's local data and stored token, not the GitHub account or GitHub resources.

## Session isolation

Introduce an account-session coordinator owned by AppDependencies. It owns the active dashboard session: a client with an account-bound token provider, account-bound PullRequestStore, notifier, and scheduler. ContentView, Settings, and the retained native status-item host observe coordinator changes rather than holding a permanently stale dashboard.

On switching: immediately clear previous PRs, badge, digest, warnings, errors, search, and pagination; stop the old scheduler; cancel tracked work; create the selected account's session; show Checking before verifying and loading that account. Preserve the selected tab, but reset its filters. No combined-account view and no background fetching for inactive accounts in this release.

Cancellation is not sufficient isolation. Every async operation captures an immutable session identifier. Check that identifier after suspension and before mutating visible state, writing activity/ledger data, or scheduling notifications. Discard results from retired sessions. Actions started in a session stay bound to that session's profile/store, never a mutable active-account pointer. Settings edits must not write an old account's repositories into the new account.

Persist the selected account for relaunch. Account selection remains available if the active token expires or GitHub is offline. Partial repository access remains a connected state with warnings. Account-specific errors do not alter other profiles' credentials or data.

## Data layout and migration

Keep refresh/notification/digest-cadence/snooze-default preferences in an app-wide settings store. Store watched repository subscriptions, overrides, notification ledger, and activity separately under profiles/<local-profile-ID>/. The digest and badge derive only from the active profile.

Migration must preserve the existing Keychain token and existing settings.json, overrides.json, ledger.json, and activity.json. After validating the legacy identity, copy legacy account-specific data into its profile directory, store its profile credential, atomically publish the registry/active profile and a migration marker, and only then retire the legacy credential. Keep legacy files as a recoverable backup; do not delete them during migration. Global settings must retain the old user's preferences.

Migration is idempotent. Failures, cancellation, locked Keychain, or offline identity checks must not erase credentials, create duplicate profiles, or mark an incomplete migration complete. Keep a legacy session usable while identity resolution is pending; show recovery guidance rather than silently creating an empty account. Validate copied data before committing migration; malformed data produces a recoverable error, not silent replacement with defaults.

Removal uses a transactional/tombstone sequence so interrupted cleanup can resume. Remove only the target profile's credential and data. If the active account is removed, select the first remaining profile in stable saved order; if none remains, clear all visible state and show onboarding. If credential deletion fails, keep the profile visible with an actionable error rather than claiming successful removal.

## Verification and release acceptance

Unit tests use injected credential stores, temporary directories, and controllable async clients—never real user tokens. Cover duplicate identities, identity-changing token replacement, migration success/retry/failure, global preferences, per-account repositories/overrides/snoozes/activity/ledgers, account removal, and active-account persistence.

Race tests switch A → B → A while requests complete out of order, including failures and pagination. Assert no retired result changes PRs, badge, connection state, digest, ledger, or notifications. Test a quick action/settings write suspended across a switch.

Extend the local E2E GitHub fixture with two identities and deliberately different PR lists. Exercise adding two accounts, switching all tabs, isolated watched repositories/triage/snooze, token expiry on one account, duplicate addition, removal, and relaunch restoring selection. Existing single-account journeys must continue to pass after fixture adaptation. Include accessible selector labels and long-login layout checks.

Before creating a PR, build/install a separate local test app and smoke-test the menu icon, selector, Settings lifecycle, switching, and relaunch. Do not alter the user's production tokens or local data. Record limits: fixtures do not prove live org SSO or real OS notification delivery. Update the README only after the feature actually ships.

## Implementation boundaries

Affected existing files: AppDependencies.swift, DashboardViewModel.swift, PRPulseApp.swift, PRPulseApplicationDelegate.swift, PRPulseStatusItemController.swift, ContentView.swift, SettingsShellView.swift, AccountSettingsView.swift, GeneralSettingsViews.swift, PullRequestStore.swift, AppSettings in Models.swift, the actual KeychainTokenStore implementation, and native E2E fixtures/tests.

Add focused AccountProfile/registry, credential-store abstraction, migration, global-preferences store, and account-session coordinator units. Locate the actual Keychain implementation first: the repository contains similarly named legacy files, so do not assume KeychainTokenStore.swift owns it. Preserve existing Keychain identifiers and test isolation hooks.

Use a separate feature/multiple-github-accounts branch at implementation time, preserving unrelated README work. Do not merge, release, or deploy to the user's production app as part of design approval.
