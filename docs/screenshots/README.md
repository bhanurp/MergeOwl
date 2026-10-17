# Documentation media

## Current Settings captures

- `settings-accounts-current.png`: two fixture profiles, `octocat` and `hubot`; only `hubot` is active. The token field is blank.
- `settings-saved-views-current.png`: `API work` matches title/repository text `API`; `Needs my review` uses the `Awaiting my review` state rule.
- `settings-view-editor-current.png`: the native saved-view editor with the `Awaiting my review` rule selected, before saving.
- `accounts-saved-views-demo.gif`: nine-second sequence with three seconds per captured state, showing accounts, the rule editor, and the saved-view list. This is an animated sequence of actual captures, not a continuous recording or an account-switching demonstration.

Captured on 2026-10-17 from the isolated E2E app containing the merged v0.2.0 implementation (`d0da600`). The app uses `Tests/E2E/github_fixture_server.py` on loopback with synthetic tokens, a separate data directory and a separate Keychain service. These are real window-content captures, not generated UI artwork. No production account or repository data is included.

## Earlier release media

`dashboard-current.png` and `prpulse-demo.gif` still show v0.1.5. The README labels them as an older-release preview. The GIF cycles through captured app states; it is not a continuous recording. Replacing these requires new popover captures from an unlocked desktop.
