# Account-workspace release QA

This is a release gate, not a claim that every check below has passed.

## Isolation

Use `bash scripts/test_e2e.sh` on a logged-in macOS desktop. It builds `dev.prpulse.e2e` with synthetic GitHub responses, a fresh data directory and Keychain service for each journey. Do not install over the user's production app, use real credentials, or change production Keychain entries.

Do not run window-opening unit tests concurrently with native journeys: they can take keyboard focus. XCUITest results and screenshots are saved under `.build/e2e/`.

## Required checks

- [x] Full Swift unit suite passes after review fixes (70 tests).
- [x] Both installer regression scripts pass using their temporary fixtures.
- [x] Python GitHub fixture tests pass.
- [x] Full native suite passes after review fixes: 15 journeys, zero failures.
- [x] Icon, badge, search, pagination, quick actions, snooze and partial access work with fixtures.
- [x] Settings opens exactly once via gear, reopen and Command-comma; closing it keeps the icon alive.
- [x] Add two accounts, switch and relaunch; isolated PRs/preferences verified natively, saved-view storage isolation covered by unit tests.
- [x] Replace a token, test without saving and confirm removal natively; identity-mismatch rejection covered by unit tests.
- [x] Saved-view creation, cancel, update, reorder, disable/delete and selection fallback work.
- [x] Default tabs and saved views fit the fixed-width popover; overflow remains reachable.
- [x] Search/tab/refresh shortcuts and standard text-editing actions work.
- [x] Light/dark appearance and long saved-view names inspected; keyboard focus covered by native shortcuts.
- [x] Local README/user-guide links resolve; labels checked against the source and native journeys.

## Evidence recorded during implementation

- Baseline: 46 unit tests passed before changes.
- Settings singleton native regression passed after replacing the duplicate scene.
- Account add/switch/relaunch native regression passed after restoring the Edit menu.
- Storage and stale-session regressions have passed locally; rerun the full suite before publication.
- All 15 native journeys passed at implementation commit `e9229ab` and again after review fixes on 2026-10-16 (`results-1792167351.xcresult`, 338.8 seconds).
- Independent review identified refresh/pagination, concurrent triage and account-removal notification cleanup bugs plus delayed-identity presentation. Deterministic regressions now pass for these sequences.
- Light and dark Settings captures were visually inspected with a long saved-view name; the light fixture explicitly uses Aqua appearance. Full-desktop captures are local QA evidence, not public documentation assets.
- Apple Silicon and Intel release builds both passed locally. Installer regressions use temporary fixture installations, not the user's production app.
- Early native runs exposed missing Edit-menu actions, header clipping and test accessibility-query issues. Those runs are failures, not release evidence.

## Limits

Fixtures do not establish live organization SSO, real macOS notification delivery, notarization, or trusted automatic updates. Releases remain ad-hoc signed and updates remain manual. Do not mark those capabilities as verified by fixture tests.
