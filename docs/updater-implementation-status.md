# Auto-update implementation status

This branch is an initial implementation, not a production-ready automatic update release.

Implemented:

- Sparkle 2.10.0 dependency, embedded framework packaging, and runtime search path.
- One app-wide updater service with injectable driver and guarded state transitions.
- Updates Settings pane, manual check, automatic-update preference and install/relaunch action.
- Fail-closed startup unless the app embeds explicit enablement, an HTTPS feed without URL credentials, a 32-byte public update key, and verification-before-extraction.
- Unit, packaging, and native unconfigured-state UI coverage.

The user approved standard Sparkle behavior on 2026-10-15: turning automatic updates off prevents future checks/downloads but does not cancel an update already staged for installation on quit.

Still required before production activation:

- Signed old-build → new-build upgrade and tampering/recovery tests using isolated throwaway apps.
- Protected signing/publication pipeline, immutable archive uploads and appcast validation.
- Maintainer-provided update key and trusted HTTPS feed.
- Developer ID signing/notarization and real release upgrade/Keychain validation.
- Default automatic-check/download settings in the production bundle after activation approval.

No production feed or key is embedded by this branch, so automatic installation remains disabled. Existing releases cannot gain this updater without a manually installed bootstrap release. Multi-account support, saved views/grouping, and the duplicate Settings-window issue are outside this initial updater PR and remain pending.
