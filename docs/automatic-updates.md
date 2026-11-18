# Automatic updates — implementation and activation

This branch adds Sparkle 2.10.1. Production updates are **not enabled** yet: the
released v0.2.4 app has no updater, and no production feed or signing key has been
configured. One manually installed bootstrap release is required before future
updates can arrive automatically. Do not advertise automatic installation until
the signed upgrade acceptance tests and production trust setup are complete.

## User experience

Updates belong to the app, independently of GitHub.com/GHES accounts. Settings →
Updates and More → Check for Updates use the same process-wide service. Manual
checks use Sparkle's native UI. Background checks/downloads do not use GitHub
account tokens or add PR polling. Downloaded, verified updates install when the
user quits naturally; Install and Relaunch is an explicit action. Disabling
automatic updates stops future checks/downloads; an already prepared update can
still install on quit. No forced restart or critical-update override is used.

The existing Tabbed/Compact preference and account, Team, CI and saved-view data
remain owned by their existing stores. Sparkle is disabled in mock/native test
builds and when trust configuration is absent.

## Required production configuration

The approved [security design](superpowers/specs/2026-10-11-secure-auto-updates-design.md)
requires explicit maintainer approval before generating the production signing
key or changing signing/hosting settings. Keep the private Ed25519 seed outside
source, artifacts and logs. Do not run `generate_keys` casually: it writes to the
login Keychain by default. The helper `scripts/update_public_key.swift` derives
only a public key from an explicitly supplied current-format seed file; it never
accesses Keychain or generates a key.

Proposed stable feed:
`https://github.com/bhanurp/MergeOwl/releases/latest/download/appcast.xml`.
This avoids introducing GitHub Pages, but still requires approval and an
operational publication order. Every subsequent stable release must carry the
signed appcast asset. A release must not become latest until its signed feed is
available, otherwise existing clients temporarily see a missing feed. Publish a
new release initially as non-latest, attach artifacts/feed, then promote it.

The bootstrap app needs these embedded Info.plist values:

| Key | Value |
| --- | --- |
| `PRPulseUpdatesEnabled` | `true` only after activation acceptance |
| `SUFeedURL` | Approved stable HTTPS appcast URL |
| `SUPublicEDKey` | Expected public Ed25519 key, 32 bytes base64 |
| `SUVerifyUpdateBeforeExtraction` | `true` |
| `SURequireSignedFeed` | `true` |
| `SUEnableAutomaticChecks` | Default `true`; existing user choice wins |
| `SUAutomaticallyUpdate` | Default `true`; existing user choice wins |
| `SUScheduledCheckInterval` | `86400` seconds; no rapid polling |

Preserve the release bundle identity `io.bhanurp.prpulse`, minimum macOS 14 and
both architecture slices. The local developer install has a different historic
identity (`dev.prpulse.app`); do not offer it production automatic updates.
Developer ID signing/notarization are additional production acceptance gates,
not replaced by ad-hoc signing or archive signatures. Preserve Sparkle's helpers,
symlinks, permissions and licenses with `scripts/package_sparkle.sh`; sign the
complete bundle and verify it strictly. No quarantine-removal workaround exists.

## Feed preparation

`prepare_appcast.py` only prepares a local feed; it never publishes anything.
Supply metadata downloaded from the GitHub release, the already uploaded
versioned ZIP, the pinned Sparkle tools, an explicitly supplied signing seed file,
and the public key embedded in that archive. Keep private files outside the
artifact/output directories. For example, after approved signing setup:

```sh
/usr/bin/python3 scripts/prepare_appcast.py \
  --archive /private/staging/MergeOwl-0.3.0-macOS-universal.zip \
  --release-json /private/staging/release.json \
  --sparkle-bin .build/artifacts/sparkle/Sparkle/bin \
  --ed-key-file /private/signing/update-seed \
  --public-key "$SPARKLE_PUBLIC_KEY" \
  --previous-feed /private/staging/previous-appcast.xml \
  --output /private/staging/prepared/appcast.xml
```

Omit `--previous-feed` only for the explicitly approved first feed. Verify the
previous feed's signature before trusting its version/build history. Preparation
rejects drafts/prereleases, mutable URLs, missing or mismatched assets,
replacement versions, decreasing/duplicate build numbers and mismatched embedded
trust. Sparkle generates/signs the archive and feed; all historical entries must
remain intact. The output is exclusively created, never overwritten by a rerun.
Upstream private signing diagnostics are suppressed to prevent malformed seed
material leaking into logs. Public release notes must never contain private keys.

The prepared `publish-appcast.yml` workflow is dispatch-only and skipped unless
`UPDATER_PUBLICATION_APPROVED=true` is explicitly configured. Dispatch it on the
approved stable tag, with that same release tag as input and the newest feed's
release as `previous_tag`. It requires protected `SPARKLE_ED25519_SEED`, public
`SPARKLE_PUBLIC_KEY` and `DEVELOPER_TEAM_ID` configuration. It checks Developer ID,
notarization, both slices and embedded trust before signing/uploading the feed,
then promotes the release. If feed upload succeeded but promotion failed, rerun
with the same tags: the workflow downloads and verifies the existing feed and
archive against the embedded public key/history, preserves the feed bytes, skips
upload, and retries only promotion. It never replaces an existing appcast. It does not create an Apple identity, notarize an
ad-hoc archive, or silently turn an unconfigured app into an enabled build.

A protected signing environment must restrict deployment refs to approved stable
tags and require a maintainer reviewer. Build jobs and pull-request jobs must not
receive the seed. Serialize publication. Do not publish a feed before its archive
exists, and do not silently replace an existing versioned asset. Protecting a job
requires actual GitHub environment rules; merely naming an environment in YAML
does not provide that protection.

## Verification and current limits

Run units and installer fixtures sequentially. The disposable runtime fixture is:

```sh
/usr/bin/python3 scripts/test_signed_update.py \
  --sparkle-root .build/artifacts/sparkle/Sparkle \
  --output /tmp/mergeowl-signed-upgrade-new-run
```

It uses a unique test bundle identity, temporary app paths/data and throwaway
seed, and never reads production Keychain. Loopback HTTP is allowed only in that
test host; the production adapter requires HTTPS. A passing fixture proves the
pinned Sparkle framework's signed natural-quit replacement and test preference
continuity. It does **not** prove real account-token continuity across Developer
ID changes, production notarization, every permission/OS condition, or resolution
of the historical intermittent SwiftUI freeze. Report failures/timeouts as such.
