# Changelog

All notable changes to PR Pulse are documented in this file.

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
