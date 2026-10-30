# Native popover design

Approved reference: side-by-side Tabbed and Compact mockup, October 30. Implement native typography, compact spacing, flat rows and restrained semantic colors. Preserve existing app behavior, account isolation, keyboard navigation and all PR actions. Tabbed remains the default; existing global preference storage remains authoritative.

## Implementation

1. Keep the fixed 420×560 native hosting bounds. Use system fonts, lightweight backgrounds/separators and stable control geometry; add no animation, blur or font downloads.
2. Tabbed: slim account/refresh/More header, visible default tabs, small saved-view shortcuts, search/filters. Compact: account header plus one row combining view picker, search and filters; recover space for PRs.
3. Shared rows: leading PR glyph, readable title and metadata, compact CI/review information, persistent icon-only Snooze and More controls with accessible names/help. Retain readiness caveats, local overrides, linked references, mute and snooze state without forcing every row to show empty labels.
4. Compute visible rows once per view render; reuse for list and footer. Avoid new subscriptions, per-row timers, network calls or list-wide animations.
5. Verify default/persisted layout tests and native journeys for both layouts, saved-view/search/filter preservation, actions, scrolling and relaunch. Visually inspect actual synthetic popover captures in dark and light appearance before creating a PR. Keep performance PR #22 separate.

## Verification evidence

- All 113 unit tests passed, including legacy/default Tabbed selection and layout persistence across stores/accounts. Final unit log: `/tmp/mergeowl-native-delivery-units.log`.
- Nine isolated Release native journeys passed locally in 320.130 seconds: light appearance/account switching, CI/mutes, saved-view/search/filter persistence and relaunch, merged references, density/actions, keyboard shortcuts, reviewed/actionable filters and quick actions, scrolling and Snooze persistence. Results: `.build/e2e/results-1793329946.xcresult`; log: `/tmp/mergeowl-native-design-journeys.log`.
- The final picker-label/accessibility refinement passed an additional native smoke test in 14.657 seconds, including visible Compact count, accessible count value and a higher first PR row than Tabbed. Results: `.build/e2e/results-1793330377.xcresult`; log: `/tmp/mergeowl-native-final-density.log`.
- Actual dark and light popover captures were visually inspected. An opaque adaptive system background replaced desktop bleed-through; no generated mockup is presented as a real app capture.
- The first baseline native attempt timed out enabling automation before executing a test. It is not passing evidence or a reproduced application failure; subsequent native runs above passed.
- Independent review found no blocking issues. Accessibility review led to adding the Actionable selected trait and Compact's explicit count value.
- Apple Silicon and Intel release builds passed (`/tmp/mergeowl-native-arm64.log`, `/tmp/mergeowl-native-x86.log`).
- Existing hosting bounds, layout storage, account identities, API behavior and production installation are unchanged. CI observation timestamps remain available in tooltips and the inspector; footer time is a fixed observation rather than a continuously ticking row label.
