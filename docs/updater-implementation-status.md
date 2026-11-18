# Auto-update implementation status — November 18, 2026

This branch contains a tested Sparkle integration and publication preparation,
**not an enabled production updater**. No production key, feed, secret or signing
environment has been created. The installed app was not launched or replaced.

Implemented:

- Exact Sparkle 2.10.1 dependency, framework/helper packaging, license notices and executable-relative runtime path.
- One app-wide updater service shared across accounts, the native app menu, popover More menu and Updates Settings. Account readiness does not disable Updates.
- Native manual checks, app-wide automatic checks/downloads and explicit Install and Relaunch. Signed background updates stage for natural quit; permission/attention cases use passive status rather than taking focus.
- Fail-closed configuration requires explicit enablement, HTTPS without URL credentials, a 32-byte embedded public key, signed feeds and verification before extraction.
- Real Sparkle regressions for opt-in ordering and terminal states, plus service/configuration and packaging tests.
- A local signed-appcast preparation tool using the pinned official Sparkle tools. It verifies archive identity/version/trust, stable immutable release metadata, monotonic build history, signatures and retained historical entries; reruns cannot replace output.
- A gated, protected-environment publication workflow. It requires explicit repository activation, approved stable-tag execution, Developer ID/notarization, universal package checks and the protected signing seed. No workflow was dispatched or remote settings changed.
- Disposable signed old→new Sparkle natural-quit upgrade with a unique test identity/path and preserved test preferences. Negative fixtures cover archive/feed tampering, wrong signing key, version rejection, offline/interrupted downloads and read-only-location deferral. These are ad-hoc, loopback test-host results, not a production notarized/Keychain acceptance claim.

The October 15 user amendment remains authoritative: disabling automatic updates
stops future checks/downloads; an already staged verified update can still install
on quit. There is no invented staged-install cancellation API.

Still required before production activation:

- Explicit approval for a production signing key, protected signing environment and stable HTTPS feed; secure backup of the private seed.
- The maintainer's Developer ID/notarization configuration and a real signed-release upgrade confirming Keychain/account continuity. These credentials are not inferred or inspected.
- Embed approved public trust/defaults in a manually installed bootstrap release. Published v0.2.4 cannot bootstrap itself.
- Inspect the actual updater UI in both layouts where local desktop automation is available; compilation and isolated framework fixtures do not replace that UI acceptance test.

Existing GHES accounts, Team PRs, saved views, native layouts and the single
Settings-window owner are retained from released v0.2.4. They are not pending
updater features. See [maintainer setup](automatic-updates.md) and the
[implementation plan](superpowers/plans/2026-11-18-complete-auto-updates.md).

November 18 verification: 156 Debug and 156 Release unit tests passed, as did both
release architecture builds, native test-target compilation, three framework
packaging tests, five publication policy/path tests, installer fixtures and the
real signing/history/recovery pipeline. Independent review findings about stale
reminders and partial publication recovery were reproduced and fixed. Local
product UI journeys, production Developer ID/Keychain acceptance and hosted CI
for the refreshed branch are not represented by these results.
