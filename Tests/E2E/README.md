# Native macOS end-to-end tests

Run on a logged-in macOS desktop with full Xcode selected and XcodeGen installed:

```sh
brew install xcodegen
bash scripts/test_e2e.sh
```

Do not interact with the desktop while XCUITest drives the app. Accept macOS automation permission if prompted locally. Results and screenshots are saved under `.build/e2e/`. Run one journey by adding `-only-testing:PRPulseUITests/PRPulseUITests/testPartialAccessKeepsAccountConnectedAndShowsPRs`.

The GitHub workflow runs on pull requests, master, feature and bugfix pushes, and manual dispatch. It uploads Xcode result bundles (including screenshots) even when tests fail.

Coverage includes the real menu-bar icon and popover, actionable badge, Settings lifecycle and quit, PR tabs/search/refresh/pagination, reviewed/actionable/N/A filters, snooze persistence, token replacement and Keychain recovery after relaunch, invalid authentication, partial-access warnings, empty state, digest, watched repositories and persisted refresh/notification preferences.

Tests build the actual app sources with a test-only compilation flag. An isolated local HTTP server supplies deterministic GitHub REST/GraphQL responses, including 401 and partial SAML-access errors. Each test uses a unique Keychain service and data directory, cleaned up after the test. No production token or GitHub secrets are needed. Production builds do not include the fixture routing or test-storage overrides.

These tests do not prove live GitHub availability, organization SSO configuration, browser navigation or delivery of macOS notifications. Notification delivery is disabled only in the E2E build to avoid permission dialogs; notification preferences are exercised through Settings. Keep fixture scenarios and journey assertions updated alongside feature changes, and keep unit tests for detailed state/ranking logic.
