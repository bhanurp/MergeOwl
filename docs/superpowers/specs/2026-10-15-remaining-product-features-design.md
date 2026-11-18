# Remaining product features — auto-updates deferred

## Scope and existing decisions

Complete multi-account login, rule-based saved views/PR grouping, and the duplicate Settings-window fix. GitHub.com and macOS 14+ only. Use Swift 6.2 and existing dependencies; do not bring Sparkle or updater UI into this work. The updater PR/worktree is preserved separately and its review monitor is paused at the user's request.

The multi-account design in 2026-10-11-multiple-github-accounts-design.md remains authoritative: one active account, separate Keychain tokens and account data, safe legacy migration, stale-request isolation, and app-wide refresh/notification preferences. Saved views belong to the active account, not global preferences.

## Saved-view model and semantics

Persist an ordered array of SavedPRView values per account: UUID id, trimmed nonempty name (maximum 40 characters), enabled flag, explicit repository names, one state rule, and optional text. Reject duplicate names within an account case-insensitively; do not overwrite an existing definition on validation failure. Decode missing saved-view data as an empty collection for migration. Invalid data must surface a recoverable storage warning without discarding the original file.

Rules: any, awaiting my review, changes requested, authored by me, TODO, and draft. Repository rules are case-insensitive exact owner/repo matches; an empty list means all tracked repositories. State rule AND repository rule AND text rule must match. Text is a case-insensitive substring of title or repository name. Awaiting-review uses the existing actionable/review-status calculation; authored matches the active verified login; changes-requested means a changes-requested review; TODO uses the local override; draft uses the GitHub draft flag.

Evaluate over the deduplicated union of PRs loaded from My PRs, Review Requested and Watched for the active account. Never claim the count covers unloaded GitHub pages. A saved view includes its scoped matching PRs; existing search/hide/actionable controls apply afterward. Its actionable count uses the existing calculator and excludes snoozed/N/A PRs, independent of search. Global badge is the unique actionable count across the active account's loaded lists, not a sum of view counts. Do not count one PR twice when it appears in multiple lists/views.

## Popover and management

Keep the existing three default tabs and show their actionable counts alongside named enabled saved views in a horizontally scrollable, keyboard-accessible tab strip. Do not widen the popover or add menu-bar items for views. Provide visible scroll affordance or an overflow menu for offscreen views. Long names must have a tooltip/accessibility label rather than hiding which view is selected.

Settings gains Saved Views with create, edit, move up/down, enable/disable and confirmed delete. Default tabs cannot be renamed or deleted. Editing uses a draft that saves atomically only after validation; Cancel leaves the saved definition unchanged. Disabling/deleting the selected view returns to Review Requested. Account switching preserves the default selected tab but never selects a saved view from another account. Selected saved view can be restored on relaunch only if it still exists and is enabled for that account.

Refresh for a saved view loads the three default sources for the active account and then recomputes membership, counts, and badge. Respect existing pagination: expose Load more for source lists with remaining pages, loading one page per eligible source; do not exhaust all repositories/pages in a tight background loop. Show loading/partial-access/error status without deleting accessible PRs. Late results from old accounts must not update any saved view or badge.

Manual per-PR collections, cloud sync, and shared/team views remain out of scope. These rule-based saved views satisfy the requested first grouping model.

## Keyboard behavior

Provide Command-1/2/3 for default tabs while the popover is active, Command-F to focus search, Command-R to refresh, and arrow-key navigation for the view strip. PR rows retain button accessibility and support focus/activation with standard macOS keyboard navigation. Avoid global hotkeys that intercept unrelated apps. Add explicit keyboard coverage for TODO/snooze through focused row controls and context menus, not undocumented global shortcuts.

## One Settings owner

Use the existing retained AppKit Settings NSWindow as the sole owner of preferences, preserving its native sidebar content and minimum 760×520 size. Remove the competing SwiftUI Settings scene and its automatic activation behavior. Bootstrap the app through a retained AppKit delegate/application entry point while continuing to host existing SwiftUI content in NSHostingController.

Route the gear button, standard Command-comma menu action, and reopen/activation handling to the same retained window. Normal launch should show the menu-bar icon without opening preferences. Closing Settings must not quit the app. Repeated opening, account switching, and relaunch must never create a second Settings window. Preserve the separate connection-error window and menu-bar badge lifecycle.

## Verification and release gates

Use test-driven implementation and temporary/injected stores. Cover account isolation and migration from the existing multi-account spec, saved-view rule combinations, duplicate PRs, count exclusion, persistence/reorder/delete/disable/cancel, bad storage, and pagination/partial failures. Verify A→B→A switching with out-of-order requests and actions in flight.

Extend native E2E fixtures to two identities. Test account add/switch/remove/relaunch, saved-view creation and membership, editing and cancellation, overflow/keyboard use, snooze exclusion, and Settings singleton through launch/reopen/Command-comma/gear cycles. Test the actual production display-name window lifecycle so the E2E title cannot hide duplicate windows. Use synthetic data and isolated Keychain services only.

Run full unit/installer/fixture/native E2E tests; build and locally smoke-test a separate app before creating PRs. Keep the user's installed app and data unchanged unless deployment is explicitly requested. Update README and changelog only to describe verified functionality; no signing/notarization or automatic-update claims. Publishing/releasing is a separate authorization step.

## Delivery sequence

1. Single-owner Settings and regression coverage.
2. Multi-account credentials, registry/migration, session isolation and UI.
3. Account-bound saved views, counts/filters, management UI and keyboard behavior.
4. Local integration testing, documentation and whole-branch review before PR creation.

Use separate focused commits and feature branches/worktrees where needed; do not merge updater code as a shortcut. No extra credentials, paid services, telemetry, or additional providers are required for these features.

Subsequent delivery authorization: the user approved implementation, README/docs updates, feature-branch publication, CodeRabbit review fixes, merge and a new release after verification. This does not authorize replacing the installed production app or enabling automatic updates.
