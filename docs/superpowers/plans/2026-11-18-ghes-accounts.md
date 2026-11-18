# GHES accounts implementation plan

**Goal:** Add enterprise-server account connection without asking users to select a server version.

**Architecture:** Canonical HTTPS server identity on each profile defaults legacy accounts to GitHub.com. Route REST/GraphQL, token links and linked references through that identity. Credentials stay keyed by profile UUID; uniqueness uses server plus user ID. Reject cross-origin credential redirects. Validate with stable identity APIs; optional feature incompatibility remains explicit unavailable data rather than preventing account creation.

**Constraints:** No production credentials or installed app changes. Preserve existing profile migration, cancellation, budgets and GitHub.com fixture routes. No claim that all historical GHES schemas support every optional feature.

- [x] Add failing endpoint/legacy decoding/host validation tests, then implement server model.
- [x] Add host-scoped identity and transport regressions, then wire validation/coordinator/client and link routing.
- [x] Add Enterprise URL settings controls and host labels, preserve existing defaults and credential identities.
- [ ] Verify full units, architecture builds and isolated both-layout/account native journeys sequentially where desktop automation permits; document limits and update onboarding.

## Verification evidence and limits

- Final full Swift suite: 126 tests pass, zero failures (`/tmp/mergeowl-ghes-final126.log`). Endpoint/model tests initially failed before implementation; pending legacy migration reproduced a lost mark before the fix; startup-cleanup regression reproduced two wrong-token activations before binding known tokens to the exact activated profile. GHES transport rejects a pinned cloud API-version header, then passes with server-native versioning.
- Synthetic REST and GraphQL identity requests are verified against the configured HTTPS host and port. Tests cover legacy decoding, server-scoped duplicate IDs, profile selection after reconnect, delayed legacy migration and redirect-origin restrictions.
- Release builds pass for arm64 and x86_64 (`/tmp/mergeowl-ghes-final-arm64.log`, `/tmp/mergeowl-ghes-final-x86.log`).
- Isolated Enterprise/same-cloud-identity and existing multi-account native journeys were added/requested. Release native target compiled, but macOS automation timed out enabling automation mode before either test executed (`/tmp/mergeowl-ghes-native.log`, results `1794971843.xcresult`). This is not passing native UI evidence. No blind retries or production app changes were performed.
- Independent targeted review identified profile selection, legacy migration and startup token pairing issues; regressions and fixes address them. Final targeted re-review found no further concrete token-host/migration blocker.
- E2E_TESTING builds route synthetic identities to the isolated loopback fixture. Normal builds derive actual HTTPS GHES REST and GraphQL routes; no TLS trust bypass is added. Tests do not establish access to a customer's private GHES, VPN, SSO or live notification delivery.
