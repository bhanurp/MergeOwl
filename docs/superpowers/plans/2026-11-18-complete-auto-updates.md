# Complete MergeOwl Auto-Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. No delegation unless separately authorized.

**Goal:** Finish the existing approved Sparkle updater for the current MergeOwl app, including secure publication tooling and a verified isolated upgrade, without touching the installed production app.

**Architecture:** Reuse the process-wide injectable updater from PR11, integrate it with the current account-aware Settings/native host, and pin stable Sparkle 2.10.1. Keep updater networking independent of GitHub account credentials. Archive/feed signatures and an embedded public trust key gate production startup; test keys and throwaway apps validate actual replacement. Signing/feed activation remains an explicit maintainer step after implementation is reviewable.

**Tech Stack:** Swift 6.2, macOS 14+, SwiftUI/AppKit, Sparkle 2.10.1, XCTest, isolated app/HTTP fixtures, Python publication tests, GitHub Actions/Releases.

**Spec:** ../specs/2026-10-11-secure-auto-updates-design.md, including the recorded October 15 user amendment: disabling automatic updates stops future checks/downloads; an already staged verified update may still install on quit. Preserve this wording rather than invent a staged-update cancellation API.

## Constraints and current evidence

- Existing feature/secure-auto-updates worktree is clean and already attached to this chat. Reuse it; preserve every other worktree.
- Current published base is v0.2.4, master d57e6c4. PR11's original integration predates accounts, branding, native layouts, Team PRs and CI monitoring, so retain those current implementations when merging.
- Sparkle's current stable release is 2.10.1, including an install-on-quit path fix. Resolve and pin it exactly; do not select 2.11 beta.
- Repository secret-name and environment metadata currently return empty lists. No production signing key/feed is configured. Do not generate a maintainer key, access production Keychain/tokens, create secrets/environment/Pages, deploy a feed or publish an updater release merely from this plan.
- v0.2.4 has no updater; one manually installed bootstrap release is necessary. Do not claim automatic updates are shipped before a signed old→new upgrade is verified and production configuration is approved.
- Prefer a stable GitHub Release appcast asset URL over introducing GitHub Pages hosting; keep immutable versioned archive URLs and signed feed content. This is a proposal for activation, not authorization to change remote settings.
- Local desktop automation recently timed out before journeys; compile/test logic independently and report runtime limits. Never work around this by replacing the user's installed app.

## Task 1 — Integrate the existing draft with current master

- [ ] Merge origin/master into feature/secure-auto-updates without rewriting published history. Resolve conflicts by keeping current account/native-host/Team/CI behavior and inserting updater integration deliberately.
- [ ] Pin Sparkle 2.10.1 and retain framework/helper license/permissions/symlinks and executable-relative rpath packaging.
- [ ] Own one AppUpdateService in AppDependencies; use a disabled driver for mocks and native fixture builds. Share it across account switches and both Settings entry points.
- [ ] Add Updates Settings and a manual Check for Updates action in the native app/menu-bar controls. Keep update controls independent of account readiness.
- [ ] Run full units, framework/installer fixtures and both architecture builds sequentially. Fix regressions without production credentials or app installation.

## Task 2 — Verify driver lifecycle, preference and trust behavior

- [ ] Read the pinned Sparkle delegate/header behavior for background download, natural-quit install, explicit relaunch and error handling. Use supported APIs only.
- [ ] Add meaningful failing regressions before fixes for missing trust configuration, duplicate checks, background errors, terminal states, staged opt-out wording, account-independent ownership and unsigned/tampered updates.
- [ ] Require HTTPS, embedded Ed25519 public key and verification before extraction; use signed feed validation when activating the stable framework's supported configuration. Development/test builds remain fail-closed unless explicitly isolated with test configuration.
- [ ] Verify the actual packaged framework/helper slices and linkage, not only Swift imports. Preserve minimum macOS 14 and both architectures.

## Task 3 — Implement reviewable publication tooling

- [ ] Build a testable appcast generator/validator around Sparkle's signing tools, with stable releases only, immutable archive URLs, length/signature, minimum OS/architectures and compatible historical entries.
- [ ] Reject existing version replacement, duplicate/decreasing build numbers, missing artifacts, mismatched versions and invalid signatures before publishing a feed. Serialize publication and keep private key values out of source, output and archives.
- [ ] Prepare a protected signing-environment workflow and maintainer instructions. Read only configuration names during preparation; no remote environment/secret changes or key generation without approval.
- [ ] Add fixture tests for publication reruns/failures and signing configuration. Keep manual downloads available and do not use GitHub account PATs in updater requests.

## Task 4 — Demonstrate an isolated signed upgrade

- [ ] Generate throwaway test keys outside production Keychain and create distinct old/new test apps, bundle IDs, installation paths and data roots.
- [ ] Demonstrate discovery → authenticated download → staged state → natural quit → new executable, then verify stored settings and isolated test credential continuity.
- [ ] Reject tampered/wrong-key archives and downgrades without changing the old executable/data; verify offline/unwritable failure presentation.
- [ ] Inspect updater UI in both layouts where desktop automation permits; keep runtime failures explicit, not counted as passing evidence.

## Task 5 — Review and activation handoff

- [ ] Review the complete diff, run relevant verification and update PR11's scope/status accurately if publication is authorized. Keep production installation disabled until trust and upgrade gates are genuinely met.
- [ ] Present concrete signing/feed configuration and test evidence for the maintainer's activation decision. Explain any required key/credential approval using the exact existing spec instruction. Do not claim a live automatic updater while signing/hosting is unconfigured.
