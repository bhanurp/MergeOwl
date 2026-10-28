# Account-workspace release QA

This is a release gate, not a claim that every check below has passed.

## CI monitoring local verification (unreleased, 2026-10-27)

- Initial CI implementation Swift suite: 95 tests, zero failures. New coverage includes CI aggregation, current/test-merge revision checks, check pagination, rate-limit backoff, partial responses, successful reruns, distinct workflows, silent baselines, restart deduplication, mute/unmute, discovery across pages, retirement, rescheduling and stale visible rows.
- The full native suite passed all 20 journeys (`results-1793064505.xcresult`). After the final monitoring and actionability refinements, the CI/both-layout/relaunch journey, saved-view/layout journey and review/actionable-filter journey passed again: 3 journeys, zero failures (`results-1793065045.xcresult`).
- The CI journey verifies failed check details and links, own-failure actionability, enabled monitoring across authored pages, 15-minute interval persistence, per-PR mute persistence, both layouts and the absence of mute actions on another author's PR.
- Actual Tabbed and Compact popover captures were inspected locally. These are synthetic test data, not new published README media. Earlier README captures retain their release labels.
- Both final arm64 and x86_64 release builds passed. Both installer regressions passed using temporary fixture applications. Local README and CI-guide links and diff whitespace checks passed.
- Independent review found that revision races could discard a page and failed refreshes could erase useful previous results. Both were fixed with regression coverage. Further regressions caught interval rescheduling, stale-row propagation and own-failure actionability.
- Initial missing-feature tests failed as expected. An early native attempt also selected the existing re-review switch instead of CI alerts; accessibility evidence identified the incorrect test ancestor selector, and the CI switch now has a dedicated identifier. These failed attempts are not passing evidence.
- Production installation, credentials and Keychain were not modified. Native fixtures suppress actual OS notification delivery; the monitoring delivery boundary is tested with a recorder. Live GitHub/organization SSO and real OS banner delivery remain manual verification limits.

See the [CI monitoring guide](ci-monitoring.md) for behavior, permissions and coverage limits.

### CodeRabbit and hosted-CI follow-up

- Both initial CodeRabbit findings were verified: GraphQL `EXPECTED` contexts now map to queued and do not suppress other failure observations; search caps have a separate, list-specific coverage channel, excluded from Watched and from token-access warnings.
- Expanded Swift suite: 97 tests, zero failures. Both architecture release builds passed again. New API regressions cover expected contexts and all three list scopes; a native fixture verifies separate Reviews/My PRs coverage messages without token-access advice.
- The initial PR native check passed, but the duplicate push run failed at an immediate post-delete assertion. The hosted screenshot already showed the view removed, and the source performs deletion asynchronously. The test now waits for disappearance and still verifies persistence after relaunch. Its local journey passed with the correction.
- An affected local rerun lost app focus while traversing Layout. The helper now activates the test app before opening that menu and waits for the requested menu item. The CI/both-layout journey and saved-view/layout journey then both passed (`results-1793066979.xcresult`, 2 journeys). The corrected deletion and new coverage journey also passed in `results-1793066824.xcresult`; that run's layout focus failure is not passing evidence.
- Latest-head hosted checks and CodeRabbit review remain merge gates; these local results do not waive them.

## Unreleased layout verification

- Tabbed (B) is the default for fresh installs and preferences without a layout key.
- Compact (A) and Tabbed share account selection, saved-view selection, search, filters, triage and keyboard shortcuts.
- More → Layout and Settings → Appearance must both save the same app-wide preference, including after account switching and app restart.
- A failed preference write must retain the previous layout and report an error.
- Verify More → Settings after switching accounts, not only on first launch.
- Native tests use synthetic accounts and isolated credentials; never replace the installed app to run this checklist.

### Local evidence (2026-10-18)

- The expanded native suite passed all 19 journeys. After review fixes, the layout/relaunch, Appearance/account-switch and reviewed-PR/readiness journeys passed again (3 journeys, zero failures).
- The full Swift unit suite passed with 79 tests and zero failures after the final review fixes.
- Persistence regressions cover old preferences, unknown layouts, account/restart persistence, failed writes, corrupt repository isolation and stale settings snapshots.
- Actual popover captures were inspected in dark and forced Aqua appearance. The test-only override explicitly sets the popover appearance; it does not change production appearance behavior.
- Apple Silicon and Intel release builds and both temporary-fixture installer regressions passed. The installed production app was not replaced.
- A native rerun with an overlapping fixture-server port failed; it is not passing evidence. The subsequent isolated rerun is the relevant result.

## Isolation

Use `bash scripts/test_e2e.sh` on a logged-in macOS desktop. It builds `dev.prpulse.e2e` with synthetic GitHub responses, a fresh data directory and Keychain service for each journey. Do not install over the user's production app, use real credentials, or change production Keychain entries.

Do not run window-opening unit tests concurrently with native journeys: they can take keyboard focus. XCUITest results and screenshots are saved under `.build/e2e/`.

## Required checks

- [x] Full Swift unit suite passes after layout review fixes (79 tests).
- [x] Both installer regression scripts pass using their temporary fixtures.
- [x] Python GitHub fixture tests pass.
- [x] Full native suite passes: 19 journeys, zero failures; the three affected journeys pass again after layout review fixes.
- [x] Icon, badge, search, pagination, quick actions, snooze and partial access work with fixtures.
- [x] Settings opens exactly once via More → Settings, reopen and Command-comma; closing it keeps the icon alive.
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
- CodeRabbit follow-up: native regressions reproduced and then verified retained-pane Add account routing and removal of the ignored settings-file editor. The hosted initial E2E run failed on an OS Notification Center dialog; that CI failure remains a publication blocker until a latest-head run passes.
- The expanded 17-journey suite passed locally on 2026-10-16 (`/tmp/prpulse-cr-full-native.log`, 287.0 seconds); 70 unit tests and both release architectures also passed after the Settings fixes.
- Hosted failure evidence identified a Python local-network permission notice over the app. The test harness now denies only that exact notice when explicitly running on GitHub Actions. A local invalid-token smoke test verifies the default-off scheme wiring; hosted verification of the handler is still required.
- The first hosted-only handler did not match native accessibility fields and the CI invalid-token journey still failed. Diagnostics expose static text through `value` and button captions through `title`, while labels can be empty. Two shared-selector unit regressions reproduce this mismatch and pass after correction; latest-head hosted validation remains required.
- Two subsequent local UI launches failed before test execution with “Timed out while enabling automation mode.” The native test target compiled, but these attempts are not passing UI evidence. The earlier full 17-journey pass remains historical evidence for the unchanged application source; the corrected harness requires a new hosted pass.
- Early native runs exposed missing Edit-menu actions, header clipping and test accessibility-query issues. Those runs are failures, not release evidence.

## Limits

### Intermittent scrolling hang investigation — 2026-10-27

- A local preview became unresponsive at sustained 100% CPU. A process sample showed the main thread repeatedly flushing SwiftUI layout transactions through lazy-list placement. The hung process was stopped; credentials and account storage were not changed.
- Isolated synthetic comparisons exercised scrolling, refresh, both layouts and CI details. Replacing relative timestamps with static text did not reduce the observed cycle warnings. Keeping the hosting controller at the popover's existing fixed 420×560 bounds reduced warnings in the comparison and remained responsive, including close/reopen.
- The sizing regression failed with automatic intrinsic sizing enabled and passed after the change. All 107 unit tests and both release architecture builds passed. Independent review found no blocking correctness issue in the sizing mitigation.
- These comparisons have not reproduced the original sustained freeze. The change is a mitigation, not proof of full resolution. Release remains blocked pending further stability verification; transient cycle warnings still occur.
- At `9724432`, all 23 native journeys passed locally (793.460 seconds), including a 336.735-second scrolling/CI/refresh/Quit journey across 12 layout transitions. Both hosted native checks and Swift checks also passed. This is responsive synthetic coverage, not reproduction of the original freeze.
- Follow-up review regressions verify that opening the popover reuses an existing default-tab reset, still queues freshness after pagination, and refreshes other contributing tabs for a restored saved view. The saved-view regression failed before narrowing the reset guard; all 111 unit tests passed afterward on 2026-10-28. Layout selection now waits for the selected layout's control to render.
- An optimized Release-mode scrolling attempt lost popover focus while another test process was running; a subsequent strictly sequential attempt timed out enabling XCUITest automation before executing any journey. Neither attempt is passing release-mode stability evidence. Final optimized verification and final-head review/checks remain required before merge/release.

### CI monitoring review follow-up — 2026-10-27

- 105 unit tests passed after the review fixes. Regressions cover rejected notification retries, independent loaded-row head/test-merge identity, CI request budgeting and verification fairness across 15 failing PRs over repeated passes.
- Failure verification has reserved request capacity and rotates independently from discovery; exhausted CI budgets leave dashboard discovery available and label retained results stale.
- The targeted native CI/both-layout journey compiled but failed before executing: XCUITest timed out enabling automation mode. This attempt is not passing native evidence; latest-head hosted checks remain required.
- Hosted runs at 0876608 exposed an outdated fresh-CI assertion after enabling alerts and immediately changing their interval. The journey now verifies failed checks in both layouts before those extra polls, and requires retained check details plus an explicit request-budget warning if the later refresh is deferred. The revised UI target builds; a passing hosted rerun remains required.

Fixtures do not establish live organization SSO, real macOS notification delivery, notarization, or trusted automatic updates. Releases remain ad-hoc signed and updates remain manual. Do not mark those capabilities as verified by fixture tests.
