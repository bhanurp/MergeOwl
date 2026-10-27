# Changelog

All notable changes to MergeOwl (formerly PR Pulse) are documented in this file.

## Unreleased

### Changed

- Rename the app to MergeOwl and use the approved transparent amber owl for the app and menu-bar icons.
- Package future releases as MergeOwl.app while retaining existing account, Keychain and local-data identifiers, plus legacy generic download aliases.
- Update onboarding and contributor documentation; existing PR Pulse releases and historical screenshots retain their original names.

## [0.2.1] - 2026-10-26

### Added

- Tabbed (B, default) and Compact (A) popover layouts with a shared, persisted app-wide preference.
- More → Layout switching and native Appearance settings with layout previews.
- Backward-compatible layout defaults for existing preferences; layout changes preserve account, view, search, filters and triage state.

### Changed

- Compact PR rows with clickable titles and secondary triage actions, grouped filters, and a quieter Activity/sync footer.
- Settings and Quit move to More; both layouts share the same data, actions and keyboard shortcuts.

## [0.2.0] - 2026-10-16

### Added

- Multiple GitHub.com account profiles with separate Keychain tokens and one active dashboard.
- Account-specific repositories, local triage, activity and saved PR views; shared refresh/notification preferences.
- Rule-based saved views with repository, state and text matching, editing, ordering and enable/disable controls.
- Loaded-data actionable counts, deduplicated global badge and app-scoped keyboard shortcuts.
- Safe, retryable legacy-data migration and isolated-account regression tests.

### Fixed

- Replaced competing Settings scenes with one retained native preferences window.
- Reject retired account responses and stop cancelled refresh timers before they run another action.
- Preserve in-memory triage state when an atomic write fails.
- Restore standard text-editing menu actions in the AppKit application bootstrap.
- Reuse an account-bound credential snapshot during a session instead of repeatedly reading Keychain for API requests.
- Honor explicit refresh during pagination and preserve triage edits made while a page is loading.
- Recompute loaded lists when delayed GitHub identity lookup completes.
- Remove a deleted account's pending and delivered profile-scoped notifications without clearing other accounts' reminders.
- Route the popover's Add account action to Account even when Settings retains another selected pane.
- Remove the Advanced action that opened an ignored profile settings file.

### Still deferred

- Automatic updates, Developer ID signing and Apple notarization. Updates remain manual.

## [0.1.5] - 2026-10-13

### Documentation

- Reworked installation, GitHub connection, Keychain persistence, and partial-access troubleshooting instructions to match the app.
- Added badges, current demo-data screenshots, and a short animated walkthrough.
- Consolidated the user guide and published multi-account and secure auto-update design documents.
- Removed recommendations to execute the unverified release installer.

### Scope

- Documentation release only; app behavior is unchanged from v0.1.4.
- Multi-account login and automatic updates are planned, not implemented.
- Existing signing/notarization and duplicate Settings window limitations remain.

## [0.1.4] - 2026-10-10

### Improved

- Retained native menu-bar lifecycle, crisp flower icon and actionable PR badge.
- Native sidebar Settings with reachable, resizable controls.
- Connected-account identity, accurate authentication errors and partial-access warnings while accessible PRs remain visible.
- Token update handoff and Keychain persistence coverage.
- Nine native macOS end-to-end journeys in GitHub Actions, plus unit, fixture and installer regression tests.

### Fixed

- App bundles now declare the required macOS 14 minimum version.
- Release packaging includes SwiftPM resource bundles and versioned DMG/ZIP downloads.

### Known limitations

- Releases remain ad-hoc signed, without Developer ID signing or Apple notarization.
- Tests use local GitHub fixtures; live organization SSO and OS notification delivery still need manual validation.

## [0.1.0] - 2026-09-12

### Added

- Native macOS menu-bar dashboard for authored PRs, review requests, and watched repositories.
- Local triage actions, snooze reminders, notifications, digest snapshots, and Keychain-backed GitHub token storage.
- Stable DMG and ZIP release artifacts for macOS 14 and newer.

### Known limitations

- PR Pulse supports GitHub and macOS only.
- The app is ad-hoc signed until Developer ID signing and notarization are available.
