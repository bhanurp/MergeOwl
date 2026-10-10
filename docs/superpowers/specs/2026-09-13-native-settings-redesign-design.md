# Native Settings Redesign

## Goal

Replace PRPulse’s unreliable separate settings window and generic form with a
native macOS preferences experience that makes GitHub setup clear, trustworthy,
and pleasant.

## Problem and root cause

PRPulse currently defines `MenuBarExtra` as its primary scene and separately
defines a `Window` for settings. Apple documents that a menu-bar-only app should
not be used with other scene types. As a result, the menu-bar gear can invoke
`openWindow` without presenting a visible settings window.

## Product decision

Use the native SwiftUI `Settings` scene. The menu-bar gear uses the platform
settings presentation mechanism, so macOS owns opening and foregrounding the
single preferences window. The custom `Window("Settings", ...)` scene and its
manual AppKit focus workaround are removed.

The app remains GitHub-only and macOS-only. Settings is a dedicated preferences
window, not a view embedded in the menu-bar popover.

## Information architecture

The settings window uses a macOS sidebar with these panes, in order:

1. **Account** — initial setup and connection health.
2. **Refresh** — launch refresh and polling interval.
3. **Notifications** — actionable review and digest preferences.
4. **Repositories** — watched repositories and notification membership.
5. **Advanced** — diagnostics, settings export, log export, and test controls.

Account opens by default. Advanced is intentionally last so operational tools
do not compete with everyday configuration.

## Account experience

Account contains a concise introduction, a masked GitHub personal-access-token
field, and a primary action that changes from **Connect GitHub** to **Update
token** when a token is stored. A secondary **Test connection** action validates
the typed or saved token. A small status card gives one of these states:

- No account connected, with a short instruction and a link to GitHub token
  guidance.
- Testing connection, with progress feedback.
- Connected, showing the GitHub login and Keychain storage confirmation.
- Connection failed, with a specific, non-secret error and recovery guidance.

Removing a stored token is available as a clearly labeled destructive action,
with confirmation.

## Visual direction

The interface follows macOS conventions rather than imitating a web dashboard:

- `NavigationSplitView` sidebar and native toolbar/window behavior.
- Generous spacing, grouped content, concise hierarchy, and SF Symbols used as
  navigational cues rather than decoration.
- A restrained PRPulse green only for positive/connected state; system semantic
  colors for warnings and errors.
- Controls grouped into cards/sections with explanatory text when a decision
  has a meaningful effect.
- No user-facing debug section outside Advanced.

## Reliability and behavior

- The gear presents the Settings scene every time, including when it already
  exists, where macOS orders it to the foreground.
- The Command-comma shortcut presents the same Settings scene.
- Settings state continues to persist through the existing settings model and
  Keychain token store; tokens are never rendered after being saved.
- A token is not sent until the user explicitly saves or tests it.
- Existing refresh, notification, watched-repository, diagnostic, and export
  behavior remains available in its designated pane.

## Implementation boundaries

- `PRPulseApp` owns the `Settings` scene.
- A small settings shell owns sidebar selection and presentation composition.
- Account connection state is isolated from the visual pane so it can be tested
  without a live GitHub request.
- Existing domain models and Keychain storage remain the source of truth.

## Tests and verification

- Add a failing test that proves the settings entry point uses the native
  presentation path, then replace the old window presenter.
- Add focused tests for account state transitions: disconnected, testing,
  connected, and failed.
- Run the full Swift suite, installer regression script, and a macOS build.
- Manually install the release and verify that the menu-bar gear and
  Command-comma open the preferences window, then test connecting a GitHub
  token without logging it.

## Non-goals

- OAuth, multiple GitHub accounts, GitLab support, cloud-synced preferences,
  and changes to PR triage behavior are out of scope for this release.
