# Secure Auto-Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. No delegation unless separately authorized.

**Goal:** Deliver verified GitHub-release updates without interrupting active use, with manual checks and user-controlled automatic updates.

**Architecture:** One app-wide updater service wraps Sparkle, independent of GitHub authentication. Packaging and a protected publication pipeline establish the update trust root. Production installation stays disabled until signed artifacts and a real upgrade are validated.

**Tech Stack:** Swift 6.2, macOS 14+, SwiftUI/AppKit, Sparkle 2.10.0 (exact dependency), XCTest/XCUITest, GitHub Actions and Releases.

**Spec:** ../specs/2026-10-11-secure-auto-updates-design.md

## Global Constraints

- Support macOS 14+, GitHub Releases distribution, and both Apple Silicon and Intel.
- Never force termination during use; install verified updates on natural quit/restart.
- No GitHub user token in update requests; no credentials in files/logs/releases.
- Missing/invalid archive signatures block installation; never remove quarantine or fall back to shell replacement.
- Preserve bundle identity, account data, Keychain credentials, and preferences.
- Developer ID signing/notarization, protected signing environment, and feed hosting are production gates; local tests use isolated test identities/keys.
- Work on feature/secure-auto-updates; preserve unrelated README and multi-account work.
- Do not generate keys, alter secrets/Pages, release, or replace the production app without specific authority.

## Review Focus

1. Staged update followed by opt-out: no silent install on quit (Task 1 gate; Task 5 regression).
2. Duplicate launch/check requests: one updater/controller and no concurrent replacement (Tasks 2 and 5).
3. Read-only/translocated installation: clear recovery instructions, no replacement/bypass (Tasks 3 and 5).
4. Interrupted/tampered upgrade: old executable and user data remain usable (Tasks 4 and 5).
5. Release rerun/racing publication: immutable versions, no decreasing feed/build or missing assets (Task 4).

## Task 1: Establish lifecycle feasibility and framework packaging

**Files:** Package.swift, Package.resolved; scripts/install_prpulse.sh; new scripts/package_sparkle.sh; Tests/InstallerTests/test_install_prpulse.sh; new docs/updater-lifecycle-validation.md.

**Interfaces:** package_sparkle.sh <app-bundle-path> <sparkle-framework-path> copies the framework and helpers preserving metadata; performs no signing or installation. Updater adapter in Task 2 consumes the embedded Sparkle module.

- [ ] Before implementation, inspect Sparkle 2.10.0 source/API for supported abort/cancellation of an already staged install-on-quit. Record exact supported calls and semantics, including whether cancellation survives relaunch. No invented cancel API or helper termination.
- [ ] Create a throwaway old/new test app pair outside production paths, using separate test signing keys. Demonstrate automatic download → natural quit installation, and staged update → opt-out → quit without installation. If the latter cannot be supported, STOP and request approval for the narrower preference wording/behavior; do not implement the approved spec incorrectly.
- [ ] Write installer assertions that the packaged app contains Sparkle.framework and expected helpers, preserves symlinks/executable permissions, and has an executable-relative framework runpath. Add missing-framework failure assertion. Run bash Tests/InstallerTests/test_install_prpulse.sh and observe failure before packaging changes.
- [ ] Pin Sparkle 2.10.0 exactly, resolve the dependency, embed through package_sparkle.sh and configure the runtime search path for SwiftPM builds. Test/E2E builds must remain compatible with the module import; do not merely copy arm64-only helper binaries into universal packaging.
- [ ] Run swift build -c release --product PRPulseApp, installer regression tests, otool linkage checks, and launch the packaged throwaway app. Require no unresolved framework paths. Record actual lifecycle experiment evidence and tested opt-out semantics.
- [ ] Commit only this task's files: build: package Sparkle and verify update lifecycle.

## Task 2: Testable app-wide updater service

**Files:** new Sources/PRPulseApp/Services/AppUpdateService.swift, UpdateState.swift, SparkleUpdateDriver.swift; App/AppDependencies.swift; new Tests/PRPulseAppTests/AppUpdateServiceTests.swift.

**Interfaces:** @MainActor protocol UpdateDriver exposes canCheckForUpdates: Bool, automaticUpdatesEnabled: Bool, start() throws, checkForUpdates(), setAutomaticUpdatesEnabled(_ enabled: Bool) throws, installAndRelaunch(), and onStateChange: ((UpdateState) -> Void)?. AppUpdateService is ObservableObject with init(driver: any UpdateDriver), start(), checkForUpdates(), setAutomaticUpdatesEnabled(_ enabled: Bool), installAndRelaunch(), and published state/canCheckForUpdates/automaticUpdatesEnabled/lastCheckAt. UpdateState cases: unconfigured(String), idle, checking, downloading(progress: Double?), ready(version: String), upToDate, failed(String).

- [ ] Write tests using a fake driver: unconfigured trust prevents start/install; double check invokes once; background failure publishes an error without quit; manual check works with automatic updates off; ready → opt-out suppresses auto-install using Task 1's proven behavior; preferences persist and are not reset on launch. Run swift test --filter AppUpdateServiceTests and confirm red.
- [ ] Implement service transitions and fake driver contract. Keep Sparkle's persisted automatic-check/download preferences authoritative rather than storing conflicting copies in AppSettings. Disabled production trust configuration yields an explanatory unconfigured state and no network checks.
- [ ] Implement SparkleUpdateDriver with one retained SPUStandardUpdaterController/delegate, delegate state mapping, last-check/can-check observation, and verified Task 1 cancellation/install-on-quit semantics. Never call immediate installation except through a user-initiated action. Download completion alone must not publish ready before verified staging.
- [ ] Own one service in AppDependencies; no account token/store input. Use injected fake/disabled driver under E2E_TESTING, with no production feed or installation path.
- [ ] Run swift test --filter AppUpdateServiceTests, then swift test. Assert all pass; commit feat: add verified update service.

## Task 3: Updates pane and reachable manual check

**Files:** new UI/Settings/UpdatesSettingsView.swift; SettingsPane.swift, SettingsShellView.swift; App/PRPulseApplicationDelegate.swift, PRPulseApp.swift; UI/ContentView.swift and App/PRPulseStatusItemController.swift only for updater host action; Tests/PRPulseAppTests/SettingsPaneTests.swift; Tests/E2E/PRPulseUITests.swift and project.yml.

**Interfaces:** UpdatesSettingsView(service: AppUpdateService); SettingsShellView(viewModel: DashboardViewModel, updateService: AppUpdateService). DashboardHostActions gains checkForUpdates: @MainActor () -> Void; noop/test call sites updated. No direct Sparkle access in view code.

- [ ] Add failing pane tests asserting Updates title, arrow.down.circle symbol, and unchanged Account default. Add native fixture journeys for current version, manual action, automatic preference, busy disabled state, ready/deferred/error states, and unconfigured build guidance. Run focused tests and observe red.
- [ ] Add Updates sidebar pane with version, last-check, progress/status, Check for Updates, Automatically download updates toggle, and explicit Install and Relaunch when ready. State that automatic updates install on next quit/restart. Errors must be readable and actionable, not modal loops.
- [ ] Inject the same service into both native and SwiftUI Settings entry points. Expose manual check through popover context/menu action without widening/clipping the header. Preserve existing Settings lifecycle; do not fix unrelated duplicate-window architecture in this task.
- [ ] Wire test fake states through compile-time E2E-only configuration, preserving existing GitHub fixture routing and tests. Include no production bypass for updater signatures.
- [ ] Run pane/unit tests and isolated focused E2E; verify normal app use remains possible during errors. Commit feat: add update controls and status.

## Task 4: Signed artifacts and fail-closed publication tooling

**Files:** .github/workflows/publish-binary.yml; new scripts/validate_update_feed.py, scripts/publish_update_feed.sh; new Tests/InstallerTests/test_update_feed.py; new docs/releasing-updates.md; updater packaging from Task 1.

**Interfaces:** validate_update_feed.py <appcast-path> <artifact-directory> --previous-build <integer> validates required fields, asset existence/size, stable versions, minimum macOS 14.0, architecture and strictly increasing CFBundleVersion; Sparkle's official tools perform cryptographic archive/feed validation. publish_update_feed.sh takes only already validated public artifacts and feed, never private key arguments.

- [ ] Write failing tests for draft/prerelease exclusion, lower/equal builds, missing files, bad sizes/signatures, concurrent/duplicate publication, and arm64-only output in a universal release. Add a same-tag rerun test: seed an existing versioned release asset, attempt publication again, require a nonzero exit before upload, and assert the original asset ID and archive bytes/digest are unchanged. Run python3 -m unittest discover -s Tests/InstallerTests -p 'test_update_feed.py' and observe red.
- [ ] Implement offline validation and maintainer procedures. Use versioned archive URLs, never latest aliases in feed enclosures. Keep prior compatible entries; do not publish before downloadable assets exist. Never treat a co-hosted SHA digest as trusted publisher authentication.
- [ ] Refactor release bundling to require both architectures instead of silently shipping arm64 when Intel build fails. Copy/sign Sparkle nested helpers in supported order, then app, notarize/staple when configured, package, sign archive with the update key, and generate appcast using Sparkle's tools.
- [ ] Add release gates for public key/feed URL and protected environment signing credentials. Missing credentials must fail production publication, not fall back to ad-hoc release. Before uploading, query the target release assets and fail if any expected versioned asset already exists; remove the existing overwrite_files: true behavior and prohibit upload --clobber. With serialized publication, duplicate/conflicting uploads must fail rather than replace assets. No secrets in PR jobs or arbitrary pull_request_target execution. Use pinned action SHAs and serialized production publication.
- [ ] Run offline tests, packaging/signature checks with test keys, and workflow syntax checks. Document exact maintainer-required environment variables/secrets and one-time manual bootstrap installation. Do not configure hosting/secrets or publish from this task.
- [ ] Commit build: add authenticated update publication gates.

## Task 5: Real isolated upgrade acceptance and documentation

**Files:** new Tests/UpdaterIntegration/README.md and scripts/test_updater_upgrade.sh; Tests/E2E/PRPulseUITests.swift; README.md, CHANGELOG.md; docs/releasing-updates.md.

**Interfaces:** test_updater_upgrade.sh --workspace <explicit-temporary-directory> requires a validated throwaway root, test bundle IDs and test feed/key; refuses /Applications, user's app support directory, or production bundle identity. No production credentials.

- [ ] Define failing assertions for old→new build replacement after natural quit, no forced termination, opt-out after staging, duplicate checks, invalid/wrong-key/tampered archive, downgrade, corrupt/interrupted download, and unwritable location. Seed test-only settings and Keychain service; assert unchanged after upgrade/relaunch.
- [ ] Implement the isolated signed two-build fixture/harness using Task 1's proven lifecycle, capturing actual version/signature before and after. Fake state UI tests are not proof of replacement/verification.
- [ ] Run swift test, both existing installer suites, feed tests, existing E2E journeys plus new updater journeys, and the real isolated upgrade harness. Report exact pass/failure evidence and any platform limitation. Do not install into the user's /Applications app.
- [ ] Update README to describe actual shipped controls/rollout, opt-out and manual install fallback; do not call production auto-updates available before release acceptance. Add Sparkle license attribution and maintainer troubleshooting.
- [ ] Review whole branch for credential exposure, unsafe replacement, lost user preferences, and lifecycle mismatch. Commit test: verify signed upgrades and document rollout.

## Production activation gate (requires maintainer authority)

- [ ] Obtain approval for proposed HTTPS GitHub Pages feed, set up protected release environment and key backups, and configure Apple credentials and public update key without exposing secrets.
- [ ] Perform signed/notarized real release-to-release upgrade and Keychain persistence check. Verify feed references downloadable immutable artifacts and signature rejection works.
- [ ] Ship the first updater-enabled release for manual installation; later release proves automatic distribution. Never claim v0.1.4 self-updates.

## Self-review

All spec sections map to Tasks 1–5 or the explicit production gate. Task 1 is an intentional lifecycle feasibility stop: staging opt-out is not assumed from toggling scheduled checks. Task 2 owns state/persistence; Task 3 owns user controls; Task 4 owns publisher trust; Task 5 proves real replacement and data preservation. Remaining external inputs are maintainer signing/hosting authority, not missing implementation decisions.
