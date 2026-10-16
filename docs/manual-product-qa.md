# Account-workspace release QA

This is a release gate, not a claim that every check below has passed.

## Isolation

Use `bash scripts/test_e2e.sh` on a logged-in macOS desktop. It builds `dev.prpulse.e2e` with synthetic GitHub responses, a fresh data directory and Keychain service for each journey. Do not install over the user's production app, use real credentials, or change production Keychain entries.

Do not run window-opening unit tests concurrently with native journeys: they can take keyboard focus. XCUITest results and screenshots are saved under `.build/e2e/`.

## Required checks

- [x] Full Swift unit suite passes on the implementation snapshot (65 tests); rerun after review fixes.
- [x] Both installer regression scripts pass using their temporary fixtures.
- [x] Python GitHub fixture tests pass.
- [ ] Full native suite passes on the final head.
- [ ] Icon, badge, search, pagination, quick actions, snooze and partial access work.
- [ ] Settings opens exactly once via gear, reopen and Command-comma; closing it keeps the icon alive.
- [ ] Add two accounts, switch and relaunch; no PRs, repository settings or saved views leak between accounts.
- [ ] Replace a token, reject an identity mismatch, test without saving, and confirm removal.
- [ ] Saved-view creation, cancel, update, reorder, disable/delete and selection fallback work.
- [ ] Default tabs and saved views fit the fixed-width popover; overflow remains reachable.
- [ ] Search/tab/refresh shortcuts and standard text-editing actions work.
- [ ] Inspect light/dark appearance and keyboard focus with long account/view names.
- [x] Local README/user-guide links resolve; labels checked against the source and native journeys.

## Evidence recorded during implementation

- Baseline: 46 unit tests passed before changes.
- Settings singleton native regression passed after replacing the duplicate scene.
- Account add/switch/relaunch native regression passed after restoring the Edit menu.
- Storage and stale-session regressions have passed locally; rerun the full suite before publication.
- Early native runs exposed missing Edit-menu actions, header clipping and test accessibility-query issues. Those runs are failures, not release evidence.

## Limits

Fixtures do not establish live organization SSO, real macOS notification delivery, notarization, or trusted automatic updates. Releases remain ad-hoc signed and updates remain manual. Do not mark those capabilities as verified by fixture tests.
