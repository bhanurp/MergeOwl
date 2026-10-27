# CI snapshot freshness

The user saw “Checks passed” while PR #19's checks were running. A manual refresh corrected it, and direct inspection confirmed the app then showed “CI running”. Live GitHub data also decoded to running; this is a refresh/presentation issue rather than evidence of a status-mapping defect.

## Scope

- Refresh the selected dashboard view when its menu-bar popover opens, independent of the retained SwiftUI view's initial appearance. Coalesce rapid opens for 30 seconds and skip already-running refreshes or retired sessions.
- Show the observation age beside CI results in both layouts. While the selected list is refreshing, show “Checking CI…” instead of presenting the previous completion as current; retain old check details in the inspector.
- Preserve notification intervals, account isolation, existing budgets, layout preferences and manual refresh. No credentials are inspected.

## Verification

Reproduce a loaded passed snapshot changing to running on reopen, verify rapid-open throttling and retirement, check the native host callback, run unit/resource/installer tests and both architecture builds, then inspect both layouts locally. Keep separate from branding PR #19 while its review completes.
