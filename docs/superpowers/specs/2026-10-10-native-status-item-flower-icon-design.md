# Native Status Item and Flower Icon Design

## Goal

Make PR Pulse reliably visible and usable from the macOS menu bar. Replace
the SwiftUI `MenuBarExtra` bridge, which creates an item in system logs but
does not reliably render on the user's desktop, with a direct AppKit status
item.

The menu-bar mark is an original, standalone amber-copper folded flower.
It has no background tile, enclosing shape, text, waveform, branch glyph, or
GitHub logo.

## User experience

- PR Pulse is always represented by a compact, visible macOS status item.
- Selecting the flower opens the existing 420 x 560 PR dashboard in a native
  popover anchored to the status item.
- The dashboard keeps its current filters, pull-request actions, connection
  status, Settings control, error window, and Quit control.
- The flower remains transparent around its silhouette. Its four short,
  folded petals use restrained amber, copper, and gold facets so it remains
  recognisable at 18-24 px.
- A coral actionable-count badge overlays the flower only when the count is
  greater than zero. The badge's accessibility label continues to state the
  actionable count.
- Native Settings and Connection Errors windows remain available and use the
  same dashboard state as the popover.

## Architecture

- `PRPulseApp` owns one `AppDependencies` instance.
- A `PRPulseStatusItemController` owns `NSStatusItem`, `NSPopover`, and the
  hosted dashboard view. It receives that same dependencies instance.
- The controller installs an AppKit button with the flower icon and toggles
  the popover on click. It updates the icon/badge as the dashboard's
  actionable count changes.
- The controller retains the status item for the process lifetime and removes
  it only during application termination.
- SwiftUI continues to own the Settings and Connection Errors scenes; the
  failing `MenuBarExtra` scene is removed.

## Asset policy

- Start from the approved flower reference render, then create a local,
  app-owned icon asset rather than depend on an external file at runtime.
- Include light and dark appearance variants if needed for contrast.
- Preserve transparent surroundings and inspect the final asset at 24 px.

## Verification

- Unit-test creation/retention of the status item, badge-count presentation,
  and popover toggle behavior with an injectable status-bar abstraction.
- Run the full Swift test suite and a release build.
- Install `/Applications/PRPulseApp.app`, launch it from a fully stopped
  state, and verify it remains alive for at least ten seconds.
- The user verifies that the flower is visible in the real menu bar and that
  clicking it opens the dashboard before any pull request is created.

## Non-goals

- No changes to GitHub token storage, API behavior, pull-request grouping, or
  saved-view product scope.
- No automatic public release as part of this fix.
