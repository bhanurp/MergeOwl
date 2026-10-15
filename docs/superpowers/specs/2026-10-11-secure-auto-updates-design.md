# Secure automatic updates

## Approved user experience

Automatically check for stable releases, download updates, and install verified updates when the user naturally quits/restarts PR Pulse. Never force termination during use. Provide a manual Check for Updates action and an automatic-updates toggle. Support macOS 14+, GitHub Releases distribution, and both Apple Silicon and Intel.

## Architecture

Use Sparkle 2 rather than custom executable downloading/replacement code. Add one process-wide updater service owned by application dependencies, independent of the active GitHub account. Its state is observable by Settings and the native menu-bar host. Wrap Sparkle behind an injectable protocol so unit and UI tests cannot replace the user's installed application.

Lock an explicitly reviewed stable Sparkle version and preserve its license notices. Adapt the custom SwiftPM app-bundling scripts to embed Sparkle.framework, required helpers, permissions, symlinks, and executable-relative runtime search paths. Inspect the packaged bundle, not just successful linking.

## Trust and release policy

Require HTTPS and Ed25519 signatures on update archives. Embed the expected public update key in the app; a digest delivered beside an artifact from the same compromised source is not a substitute for an independent signing trust root. A missing/invalid signature or missing trust configuration blocks automatic installation; never fall back to the shell installer or remove quarantine to recover.

Keep the private update key outside the source tree, logs, and release downloads. Generate it on the maintainer's trusted machine only with explicit approval; back it up securely. Store signing credentials in a protected GitHub release environment, limit workflow/token permissions, and require approval for signing/publication so arbitrary PR code cannot access them. Do not print or inspect secret values.

Developer ID signing and notarization are the recommended production release gate for this product, in addition to archive signatures. They require the maintainer's Apple Developer membership/certificate and notarization credentials; they are not created by assuming permission or substituting ad-hoc signing. Keep an unsigned development/test mode separate, with production updates disabled. Ed25519 authenticates archives independently; Apple notarization addresses a different trust/distribution concern.

Use a stable HTTPS appcast as the update feed, with versioned immutable GitHub Release archive URLs. Proposed feed: https://bhanurp.github.io/prpulse/appcast.xml, subject to maintainer approval before enabling GitHub Pages. Pages is not currently configured. Do not put GitHub PATs in the appcast or updater requests. Public release downloads do not use the connected user's GitHub credential.

Publish artifacts successfully before publishing a feed item that points to them. Feed entries declare minimum macOS, supported architecture, display version, monotonic build version, archive size/signature, and release notes. Stable users never receive drafts/prereleases or older/equal builds. Keep compatible historical entries so an older OS does not get offered an incompatible release. Serialize publication and reject duplicate/decreasing build numbers; workflow run numbers alone must be audited across reruns/workflow changes.

## Controls and states

Add an Updates Settings pane with current version, Check for Updates, Automatically download updates (enabled by default in production), last-check time, and progress/status. Explain that turning this off disables future scheduled checks/downloads but manual checks remain available. User-approved amendment (2026-10-15): a verified update already staged by Sparkle still installs on quit; the preference description must state this explicitly.

States: disabled/unconfigured, idle, checking, downloading, ready for next restart, up to date, and failed. Surface invalid signatures, read-only/translocated app location, network errors, and installation permission problems with actionable text. A background failure must leave the running app usable and must not present repeated modal alerts. Manual checks may use Sparkle's standard UI. When ready, offer an explicit Install and Relaunch action but never invoke it without the user's choice.

Implement install-on-natural-quit through supported Sparkle behavior/delegates. Confirm the selected Sparkle release's APIs guarantee the agreed lifecycle; do not equate download completion with installation or force a restart to fake it. If Sparkle cannot deliver that behavior, report the mismatch before implementing an alternative. Avoid emergency/critical-update settings that override the no-interruption promise.

## Persistence and account safety

Updater preferences are app-wide and do not switch with GitHub accounts. Preserve Keychain tokens, profile data, watched repositories, triage/snooze, activity, and existing preferences through updates. Stable app bundle identity and Developer ID signing identity must be preserved across releases; test Keychain access across an actual upgrade. Do not promise silent upgrades in system locations requiring administrator authorization.

## Rollout

v0.1.4 contains no updater or embedded signing key and cannot bootstrap itself. Ship one manually installed updater-enabled release first. Only announce automatic updates after an older updater-enabled build successfully discovers, verifies, stages, and installs a newer build. Keep manual DMG downloads available.

Do not enable production auto-install until the signing key, protected release signing, feed hosting, bundle packaging, and upgrade validation are ready. Test feeds and throwaway apps use separate test keys, bundle identities, installation directories, Keychain services, and data roots. Never run upgrade tests against /Applications/PRPulseApp.app or user credentials.

## Acceptance tests

- Unit tests: enabled/disabled preferences, manual availability, staged-update opt-out, state/error presentation, no active-account coupling, and duplicate checks.
- Feed/publication tests: stable filtering, monotonic versions, missing artifacts, bad size/signature, incompatible OS/architecture, and secrets absent from public output.
- Packaging checks: framework/helper embedding, both architectures, runtime paths, strict code-signature verification, notarization/stapling when configured, and real packaged launch.
- Isolated native E2E: update available/up-to-date, progress, decline/defer, opt-out, invalid-signature rejection before installation, offline recovery, natural quit then relaunch, unchanged settings/tokens, and unwritable location messaging.
- Negative upgrade tests: tampered archive, wrong update key, interrupted download, corrupted archive, and rejected downgrade must leave the previous app/data usable.
- Local validation before any PR: inspect the updater UI and complete one isolated old-build → new-build update using signed test artifacts. Real Developer ID/notarized release upgrade remains a release acceptance step, not a mocked claim.

## Files and scope

Modify Package.swift, AppDependencies.swift, native host actions and Settings shell/panes, scripts/install_prpulse.sh, and .github/workflows/publish-binary.yml. Add a focused updater service/protocol, UpdatesSettingsView, appcast generation/publication tooling, tests, and maintainer signing instructions. Keep updater integration on feature/secure-auto-updates, separate from README and multi-account work. Do not generate keys, configure Pages, change secrets, publish, or deploy merely because this design file exists.

## Sources

- https://sparkle-project.org/documentation/ — framework embedding, archive signatures, appcast, distribution.
- https://sparkle-project.org/documentation/programmatic-setup/ — updater lifetime and manual-check integration.
- https://sparkle-project.org/documentation/customization/ — user preferences and update behavior.
