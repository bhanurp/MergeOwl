# Documentation media

## Current popover captures

- `popover-current.png`: native Review Requested popover with `octocat`, loaded counts, `API work`, and two fixture PRs.
- `popover-saved-view.png`: the same popover with `API work` selected and only its matching PR shown.
- `switch-accounts.gif`: nine seconds; `octocat` review requests → account menu → `hubot` PRs.
- `select-saved-view.gif`: six seconds; Review Requested → `API work` results.
- `snooze-and-filter.gif`: nine seconds; matching PR → Snooze menu → Hide snoozed result after selecting one hour.

Each GIF holds each captured state for three seconds. These are actual native popover screenshots, not mockups or continuous recordings. The native menus are included. Popover content is cropped to exclude desktop edges, and GIFs are resized to 420 pixels wide.

Captured on 2026-10-17 using a temporary native XCTest capture journey against the v0.2.0 app source. The journey passed (one test, zero failures); its temporary test method is not shipped. It used the local GitHub fixture server, synthetic `octocat`/`hubot` credentials, and randomly isolated data/Keychain storage cleaned by test teardown. No production credentials were inspected or changed. The separate full-desktop teardown attachment is not published.

## Current Settings captures

- `settings-accounts-current.png`: two fixture profiles, `octocat` and `hubot`; only `hubot` is active. The token field is blank.
- `settings-saved-views-current.png`: `API work` matches title/repository text `API`; `Needs my review` uses the `Awaiting my review` state rule.
- `settings-view-editor-current.png`: the native saved-view editor with the `Awaiting my review` rule selected, before saving.
- `accounts-saved-views-demo.gif`: nine-second sequence with three seconds per captured state, showing accounts, the rule editor, and the saved-view list. This is an animated sequence of actual captures, not a continuous recording or an account-switching demonstration.

Captured on 2026-10-17 from the isolated E2E app containing the merged v0.2.0 implementation (`d0da600`). The app uses `Tests/E2E/github_fixture_server.py` on loopback with synthetic tokens, a separate data directory and a separate Keychain service. These are real window-content captures, not generated UI artwork. No production account or repository data is included.

## Earlier release media

`dashboard-current.png` and `prpulse-demo.gif` show v0.1.5 and are retained as a clearly labeled older-release preview. The GIF cycles through captured app states; it is not a continuous recording. The current popover previews are listed above.
