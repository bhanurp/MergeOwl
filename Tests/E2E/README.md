# Native macOS end-to-end tests

Run on a logged-in macOS desktop with full Xcode selected and XcodeGen installed:

```sh
brew install xcodegen
bash scripts/test_e2e.sh
```

Do not interact with the desktop while XCUITest drives the app. Accept macOS automation permission if prompted locally. Results and screenshots are saved under `.build/e2e/`. Run one journey by adding `-only-testing:PRPulseUITests/PRPulseUITests/testPartialAccessKeepsAccountConnectedAndShowsPRs`.

The GitHub workflow runs on pull requests, master, feature and bugfix pushes, and manual dispatch. It uploads Xcode result bundles (including screenshots) even when tests fail.

Coverage includes the real menu-bar icon and popover, actionable badge, Settings lifecycle and quit, PR tabs/search/refresh/pagination, reviewed/actionable/N/A filters, snooze persistence, token replacement and Keychain recovery after relaunch, invalid authentication, partial-access warnings, empty state, digest, watched repositories and persisted refresh/notification preferences.

Account-workspace journeys add two distinct GitHub identities, explicit account switching and relaunch restoration, saved-view creation/cancel, a singleton Settings window reopened with Command-comma, popover bounds checks, and Command-1/2/F keyboard navigation. Unit tests cover storage failures, migration retries, per-profile credential isolation and out-of-order A→B→A requests. Native journey failures are release blockers; a failed run is not replaced by a unit-only pass.

Hosted GitHub Actions runners can display a Python local-network permission dialog even though the fixture server binds only to `127.0.0.1`. The runner-only interruption handler denies that exact Python/find-devices/local-networks notice so it cannot cover app controls. It does not grant LAN access, handle unrelated permission dialogs, or run during normal local test invocations. The script forwards the hosted-runner flag explicitly through the test scheme; it does not change production app behavior or OS settings with shell commands.

The light-appearance journey uses a test-only per-process AppKit appearance override. It does not change macOS appearance preferences. Review the captured screenshot as well as the test result; a test name alone does not establish visual coverage.

Tests build the actual app sources with a test-only compilation flag. An isolated local HTTP server supplies deterministic GitHub REST/GraphQL responses, including 401 and partial SAML-access errors. Each test uses a unique Keychain service and data directory; teardown removes all credentials in that test service, including profile-specific entries. No production token or GitHub secrets are needed. Production builds do not include the fixture routing or test-storage overrides.

These tests do not prove live GitHub availability, organization SSO configuration, browser navigation or delivery of macOS notifications. Notification delivery is disabled only in the E2E build to avoid permission dialogs; notification preferences are exercised through Settings. Keep fixture scenarios and journey assertions updated alongside feature changes, and keep unit tests for detailed state/ranking logic.
