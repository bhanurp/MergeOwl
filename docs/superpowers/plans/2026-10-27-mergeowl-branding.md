# MergeOwl Branding Implementation Plan

**Goal:** Apply the approved MergeOwl name and transparent amber owl to the app, repository and current docs.
**Architecture:** Preserve account storage, Keychain services, bundle IDs and internal Swift target names. Rename the visible brand, executable product and new release assets; retain truthful historical release/media labels.
**Tech Stack:** SwiftUI/AppKit, SwiftPM, PNG/ICNS, GitHub Actions and repository API.

## Approved choices and constraints

The user chose MergeOwl, approved the generated transparent owl and explicitly requested the app/repository rename and README/docs update. Keep macOS 14, manual updates and signing caveats. Do not inspect or modify production credentials, account storage or the installed application. Preserve PR18's separate review checkout; rebase this branch onto its eventual squash merge before publication.

## Tasks

- [ ] Add failing branding/icon and installer regressions; retain badge and account compatibility coverage.
- [ ] Package the approved PNG/transparent ICNS and render the owl with the existing actionable badge in production and E2E.
- [ ] Rename visible strings, SwiftPM executable product and new release app/assets to MergeOwl; retain legacy internal identities.
- [ ] Update installers/release workflow and verify an isolated real bundle and temporary installer fixtures.
- [ ] Update current README/guides/contribution/security/issue text and canonical links; preserve old asset names and media labels, and mark branding unreleased.
- [ ] Run unit tests, both architecture builds and both-layout native/persistence tests; inspect icon captures and obtain independent review.
- [ ] Reconcile PR18 merge and rebase branding commits, rename repository to bhanurp/MergeOwl after local verification, update remotes/follow-ups, verify repository identity, PRs and releases.
- [ ] Push a focused branding PR through the established review-before-merge workflow. No release or production installation is included.

## Review focus

Resource lookup must work in SwiftPM and native test bundles. Preserve saved credentials/accounts. Existing releases still contain PRPulseApp files. Links, badges and future installer filenames must agree. The repository rename must preserve repository ID and open PR workflows.

## Verification evidence

- 96 unit tests passed, including packaged owl transparency/visibility and actionable-badge rendering.
- Apple Silicon and Intel release builds passed; both temporary installer regression suites passed.
- README/contributor/branding-guide/CI-guide local links and whitespace checks passed.
- Independent read-only review found no important issues; remaining fallback label corrected.
- Native full suite and targeted status-item retry both failed before test execution: XCUITest timed out enabling automation mode. Native verification remains pending; this is not a passing UI result.
- GitHub repository renamed to bhanurp/MergeOwl with unchanged repository ID 1162775146; v0.2.1 remains accessible. Shared origin and CI follow-up updated.
- Branding remains based on CI PR18 until its findings are resolved. Keep the branding PR draft until native checks and dependency reconciliation complete.
