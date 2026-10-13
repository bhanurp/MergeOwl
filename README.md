# PR Pulse

<img src="Sources/PRPulseApp/Resources/PRPulseFlower@2x.png" width="72" alt="PR Pulse flower icon">

[![Latest release](https://img.shields.io/github/v/release/bhanurp/prpulse)](https://github.com/bhanurp/prpulse/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111827?logo=apple&logoColor=white)](#install)
[![MIT license](https://img.shields.io/github/license/bhanurp/prpulse)](LICENSE)
[![Swift tests](https://github.com/bhanurp/prpulse/actions/workflows/test.yml/badge.svg?branch=master)](https://github.com/bhanurp/prpulse/actions/workflows/test.yml)
[![macOS E2E](https://github.com/bhanurp/prpulse/actions/workflows/e2e.yml/badge.svg?branch=master)](https://github.com/bhanurp/prpulse/actions/workflows/e2e.yml)

Keep your GitHub pull requests one click away, in your Mac’s menu bar.

PR Pulse brings together PRs you authored, reviews requested from you, and repositories you watch. Find what needs attention, open a PR on GitHub, or snooze it until later—without keeping another dashboard open.

[Download latest release](https://github.com/bhanurp/prpulse/releases/latest) · [Report a problem](https://github.com/bhanurp/prpulse/issues) · [Release notes](CHANGELOG.md) · [Contribute](CONTRIBUTING.md)

## A quick look

<img src="docs/screenshots/dashboard-current.png" width="472" alt="PR Pulse popover showing review requests, PR actions, and connected account status">

Your reviews, your PRs, and your next action—one compact popover.

### Switch views and focus on actionable PRs

![PR Pulse demo cycling through Review Requested, My PRs, and the Actionable filter](docs/screenshots/prpulse-demo.gif)

Real app captures with synthetic GitHub fixture data. The GIF cycles through captured states, rather than recording browser navigation. No personal tokens or private repositories are shown.

**Requirements:** macOS 14 or newer, an Apple Silicon or Intel Mac, and a GitHub.com account with a personal access token. No Xcode is needed for the download.

**Early release:** the app is ad-hoc signed, not Apple-notarized. Read the first-launch instructions below before installing. GitHub.com and macOS are the supported targets; GitLab, Windows, Linux, and custom GitHub Enterprise Server hosts are not supported.

## Install

1. Open the [latest release](https://github.com/bhanurp/prpulse/releases/latest) and download **PRPulseApp.dmg**. The universal build supports Apple Silicon and Intel.
2. Open the DMG and drag **PRPulseApp.app** into **Applications**.
3. Launch **PRPulseApp.app** from Applications.
4. Look for the orange flower icon in the menu bar at the top of your screen. Click it to open the PR list. This is a menu-bar app, not a normal Dock window.

### If macOS blocks the first launch

Because the release is not notarized, macOS may warn that it cannot verify the developer. Only proceed if you downloaded it from this repository’s Releases page and trust the software.

After attempting to open the app, go to **System Settings → Privacy & Security → Open Anyway**, then confirm **Open**. See [Apple’s instructions and security explanation](https://support.apple.com/en-us/102445). Do not disable Gatekeeper globally or override a malware warning.

Use the manual DMG installation above. Automated release installation is not recommended until publisher-authenticated artifact verification is implemented. Current releases are not notarized; downloading from this repository does not substitute for that verification.

## Connect GitHub

PR Pulse does not automatically reuse your browser or GitHub CLI login. Connect your account inside the app.

### Create a token

1. Open [GitHub’s fine-grained token settings](https://github.com/settings/personal-access-tokens/new).
2. Name the token, for example **PR Pulse**, and choose an expiration date.
3. Select the **Resource owner** that owns the repositories you want to follow. Under **Repository access**, select those repositories.
4. Set **Pull requests: Read-only**. **Metadata: Read-only** is included automatically. Additional data or organization policy may require additional access; do not grant write permissions just to dismiss a warning.
5. Generate the token and copy it. GitHub only shows its value once.

A fine-grained token is limited to one resource owner. Organization approval may be required, and some collaborator or multi-organization workflows need a classic token instead. See [GitHub’s token guide and limitations](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

For a classic token, use [GitHub’s classic token settings](https://github.com/settings/tokens). Private-repository access uses the broad `repo` scope; organization visibility may need `read:org`. These scopes are broader than read-only access: use a fine-grained token where possible, follow your organization’s policies, and authorize SSO access if required.

### Save and verify the connection

1. Click the flower menu-bar icon, then the **gear** button to open Settings.
2. Select **Account** in the sidebar.
3. Paste the token into **Personal access token**.
4. Click **Connect GitHub** (or **Update token** if already configured).
5. Wait for **Connected as `<your username>`**. Return to the popover and click the **refresh** button.
6. Choose **My PRs** or **Review Requested**. An empty list can be correct if you have no matching open PRs.

**Test connection** checks a token but does not save a newly entered token. If the status says **Token verified — save to connect**, click **Connect GitHub** or **Update token** to persist it.

Tokens are stored in macOS Keychain, not plaintext settings. The input intentionally becomes blank after saving and when Settings reopens; this does not mean the saved token was lost. Check the connection status or use **Test connection** without entering a token.

## Use PR Pulse

### Find the PRs that matter

- **My PRs:** open PRs authored by you.
- **Review Requested:** open PRs requesting your review.
- **Watched:** open PRs in repositories added under **Settings → Repositories**. Enter `owner/repo`, for example `apple/swift`, and click **Add**.

Search by title or repository. Use **Actionable**, **Hide reviewed**, **Hide snoozed**, and the not-applicable filter to narrow the list. If PRs seem missing, clear search and turn off filters first.

The menu-bar badge counts actionable PRs. Click the icon to see the list; the PR list is not displayed directly in the menu bar.

### Triage without changing GitHub

Open a PR on GitHub, mark it **TODO** or **N/A**, or use **Snooze** to defer it. Triage and snooze are local app actions; they do not submit a GitHub review or merge a PR.

### Tune refresh and notifications

- **Settings → Refresh:** choose the refresh interval and whether to refresh on launch.
- **Settings → Notifications:** configure re-review and new-review-request alerts, digest cadence, and default reminder time. Allow notifications in macOS System Settings if prompted.
- **View digest:** open the activity summary from the popover footer.
- **Settings → Advanced:** refresh immediately, test a notification, or export diagnostics.

## Troubleshooting

| What you see | What to do |
| --- | --- |
| No icon or app window | Launch `PRPulseApp.app` from Applications and check the first-launch warning. Look in the menu bar, including any hidden-items area managed by a menu-bar utility. |
| **Couldn’t connect to GitHub** or a 401 error | Check token expiration/revocation, paste a replacement under **Account**, and click **Update token**. |
| Connected, with an orange access warning | Authentication succeeded, but some PR data is inaccessible. Accessible PRs remain visible. Check repository selection, organization approval, and SSO authorization; see details under **Account**. |
| No pull requests | Clear search/filters, refresh, and check the selected tab. **Watched** requires configured repositories. Compare with open PRs visible to your account on GitHub. |
| Token field is blank after relaunch | This is intentional. Check the connection status or use **Test connection** without entering a token. |
| Repeated Keychain prompts | Use one installed app copy; development and release builds can have different identities/signatures. Do not delete your Keychain as a workaround. Report persistent prompts. |
| Two Settings windows | A known activation issue is tracked in [#9](https://github.com/bhanurp/prpulse/issues/9). Close the extra window and use the one opened by the popover’s gear button. |
| Notifications do not arrive | Check macOS notification permission and **Settings → Notifications**. Live OS delivery is not covered by automated fixture tests. |

Still stuck? [Open an issue](https://github.com/bhanurp/prpulse/issues) with your macOS version, app release version, reproduction steps, and error text. Redact tokens, private repository names, and sensitive information from screenshots or exported logs. Never paste a token into an issue.

## Update or uninstall

To update, quit PR Pulse using the popover’s power button, download the latest DMG, replace the app in Applications, and launch it again. App replacement does not intentionally remove your Keychain token or local preferences.

To uninstall, quit the app and move **PRPulseApp.app** to Trash. To remove its stored credential first, use **Settings → Account → Remove token**. Revoke the token on GitHub if no longer needed. Removing the app alone does not remove Keychain credentials or local preferences.

## Current scope and roadmap

Available today: three PR lists, actionable badge, search and filters, local triage, snooze, watched repositories, refresh preferences, notification preferences, digest, and Keychain-backed token storage.

**Planned, not shipped:** named saved views, user-defined PR grouping, [multiple GitHub accounts](docs/superpowers/specs/2026-10-11-multiple-github-accounts-design.md), and [secure automatic updates](docs/superpowers/specs/2026-10-11-secure-auto-updates-design.md). The latter two have design documents, not working implementations. Signing/notarization and first-run polish remain release-readiness priorities. See the [product roadmap](docs/superpowers/specs/2026-09-12-prpulse-public-product-roadmap-design.md), [open issues](https://github.com/bhanurp/prpulse/issues), and [changelog](CHANGELOG.md). Roadmap items are intentions, not promises of availability.

## Build and test from source

Source builds require macOS 14+ and Swift 6.2 or newer. Native UI tests also require full Xcode, a logged-in desktop, and XcodeGen.

```bash
git clone https://github.com/bhanurp/prpulse.git
cd prpulse
swift test
bash scripts/install_prpulse.sh
open "$HOME/Applications/PRPulseApp.app"
```

The installer builds and packages a local development app. Its bundle identity/version metadata differs from the published release; do not treat it as the official downloaded build or run both copies together.

Installer regression tests:

```bash
bash Tests/InstallerTests/test_install_latest_release.sh
bash Tests/InstallerTests/test_install_prpulse.sh
```

Native end-to-end tests:

```bash
brew install xcodegen
bash scripts/test_e2e.sh
```

Read the [E2E guide](Tests/E2E/README.md) first: UI tests control the desktop. CI exercises isolated GitHub fixtures, not your account. These tests do not prove live organization SSO, external browser navigation, or macOS notification delivery.

## Contribute and support

Read [CONTRIBUTING.md](CONTRIBUTING.md) for development and PR expectations, and [SECURITY.md](SECURITY.md) for vulnerability reporting. PR Pulse is available under the [MIT license](LICENSE).

Found PR Pulse useful? Star the repository to help other developers discover it. Reproducible bug reports, onboarding feedback, and documentation fixes are equally welcome.
