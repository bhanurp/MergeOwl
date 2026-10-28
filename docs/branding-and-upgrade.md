# MergeOwl rename and upgrade

MergeOwl is the new product name for PR Pulse. The name and amber owl artwork were approved by the maintainer. The icon is an owl-shaped transparent cutout, with the existing actionable-PR badge in the menu bar. It has no enclosing square or circular background.

## Release availability

The MergeOwl name and owl are introduced in v0.2.2. v0.2.1 and earlier GitHub releases remain named PR Pulse/PRPulseApp and contain the original flower icon. Existing screenshots and GIFs are labelled with their original versions; they are not previews of the owl release. The README logo uses the approved new owl.

Release packaging from v0.2.2 produces `MergeOwl.app`, generic `MergeOwl.dmg`/`MergeOwl.zip` downloads and versioned MergeOwl archives. The release workflow also emits the legacy generic `PRPulseApp.dmg`/`PRPulseApp.zip` aliases so existing download paths can continue to work. Existing published release assets are not renamed.

## Upgrade when the renamed release is available

1. Quit PR Pulse using its menu's Quit action.
2. Download the MergeOwl release from [GitHub Releases](https://github.com/bhanurp/MergeOwl/releases).
3. Install and launch `MergeOwl.app`; look for the owl in the menu bar.
4. Verify your saved accounts and settings, then remove the old `PRPulseApp.app` application copy to avoid duplicate launches.

Do not delete account data, profiles or Keychain items as part of this rename. The existing application-support paths, Keychain service names, account IDs and bundle identifiers are intentionally unchanged. The token field still becomes blank after saving; use account connection status to confirm the saved credential.

Ad-hoc signing can still produce macOS trust or Keychain access prompts. The rename does not add Developer ID signing, notarization or automatic updates. Updates remain manual.

## Repository and source compatibility

The canonical repository is [bhanurp/MergeOwl](https://github.com/bhanurp/MergeOwl). Update an existing clone with `git remote set-url origin https://github.com/bhanurp/MergeOwl.git`. Existing repository history, issues, pull requests and releases remain part of the same GitHub repository.

Internal source directory and module names such as `Sources/PRPulseApp`, existing test identifiers and legacy installer script names are retained. Build the renamed executable with `swift build -c release --product MergeOwl`; run tests with `swift test`. A source checkout may still reside in a local folder named PRPulse without affecting the app name.
