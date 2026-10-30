# Performance audit and optimization

Preserve both layouts, account isolation, freshness semantics, manual refresh, and live failure revalidation. No production account, installed-app, or Keychain access is needed.

1. Measure duplicate simultaneous CI reads with a delayed synthetic HTTP transport. Coalesce only overlapping discovery reads on the same client and PR; do not cache completed results or coalesce failure revalidation. Verify distinct clients, failures and subsequent refreshes.
2. Remove repeated full-list scans while retaining previous CI snapshots during page enrichment. Build one lookup per page, preserving existing selection semantics and revision/staleness behavior. Measure lookup work with a large synthetic dataset.
3. Audit view publication and disk/network work for main-thread stalls. Record findings and remaining risks without speculative UI rewrites.
4. Run unit/regression tests and release builds. Exercise both layouts using isolated fixtures if desktop automation works; record startup failures accurately. Request independent review before delivery. Do not publish or install as part of this audit.

## Evidence and findings

- Delayed synthetic HTTP transport: four overlapping reads of one PR made 12 requests before sharing, versus 3 afterward (snapshot, check-context page, revision verification). Subsequent reads remain fresh, notification failure revalidation bypasses sharing, and separate client/account instances do not share work.
- Release-mode comparison with identical 2,500-row fixture: three page refreshes took 3.339 seconds with the original repeated scans and 0.164 seconds with one lookup. The temporary baseline was restored only for measurement, then the optimization reinstated. These are local synthetic data-processing timings, not production network latency or frame-rate measurements.
- Shared-request cancellation must remove each cancelled waiter promptly, cancel the underlying operation when its final consumer leaves, and keep another consumer alive. Independent review identified this requirement before delivery; cancellation regression coverage is included.
- Remaining audit risks: saved-view access repeatedly deduplicates/sorts loaded rows while rendering counts; initial presentation can request overlapping list refreshes; CI monitor observation persistence writes JSON synchronously on the monitor's main actor. These need separate profiling before caching or changing persistence/refresh semantics. No speculative caching, wider request concurrency, reduced freshness, or polling-interval changes were introduced.
- Original intermittent SwiftUI layout freeze is not proven resolved by this performance work. Keep the prior fixed-host mitigation and test both layouts without substituting synthetic tests for real-account/OS notification validation.

## Verification

- Final debug and release suites: 117 tests passed in each configuration. Final release benchmark: 0.170 seconds for three 2,500-row refreshes versus the 3.339-second baseline (about 19.6× faster for this isolated path).
- Apple Silicon and Intel release builds passed.
- Initial isolated Release native run: CI monitoring/mute persistence and scrolling/layout/CI/refresh/Quit journeys passed in 178.042 seconds total. This preceded the cancellation refinement; a final native rerun verifies the delivered code separately.
- Final delivered-code Release native rerun passed both journeys in 175.887 seconds: CI monitoring/mutes in both layouts (56.822 seconds) and scrolling/layout/CI/refresh/Quit (119.064 seconds). Results: `.build/e2e/results-1793326085.xcresult`; log: `/tmp/mergeowl-performance-final-native.log`.
- Independent review approved the indexing change and cancellation-aware request sharing. Cancellation uses an explicit test latch rather than assuming completion within a fixed delay.
- All data/transport fixtures are synthetic. Production credentials, installed application and Keychain were not inspected or changed. Changes are local on `codex/performance-audit`; no release or remote publication is part of this task.

## PR review follow-up

- Publishing and merging were subsequently authorized in PR #22. CodeRabbit identified a cancellation/result race: the cancelled consumer could receive a successful result or an unrelated error before waiter removal ran. A 200-case regression reproduced 103 incorrect outcomes before the fix. Post-await cancellation checking and error normalization now preserve cancellation in both paths.
- The large-page test now assigns a unique check ID to every row and then refreshes with unavailable CI, verifying that all 2,500 PRs retain their own check rather than a neighboring row's data.
- Both debug and release suites passed all 118 tests after these fixes; independent review approved. The original PR head's hosted Swift and native checks passed. Final pushed-head review/checks remain required before merge. No release or installation is requested.
