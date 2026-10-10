# PR Pulse Menu-Bar Icon Design

## Goal

Replace the generic monochrome branch symbol with a compact, recognisable PR
Pulse mark that feels as expressive and premium as a modern audio-wave icon,
while remaining clear in the macOS menu bar.

## Visual concept

The mark is a dark, softly rounded square containing a vivid pink-to-violet
waveform. The waveform is entirely abstract: a short sequence of rounded peaks
and valleys that feels like live signal activity, rather than an illustration of
a Git branch or a pull request.

The product name supplies the PR meaning; the mark supplies energy, rhythm, and
an immediately recognisable product identity at menu-bar scale.

## States

- **Idle / no actionable PRs:** dark charcoal tile with the pink-to-violet
  pulse line; calm, high-contrast, and recognisable.
- **Actionable PRs:** retain the branded pulse line and add a small warm coral
  count badge at the top trailing edge. The badge never replaces the mark.
- **Accessibility:** provide a descriptive `accessibilityLabel` that includes
  the actionable count. Do not rely on colour alone for the count.

## Implementation

Implement the mark as a SwiftUI vector view inside `BadgeIcon`, rather than a
raster asset. A vector mark stays sharp at menu-bar scale and supports system
appearance changes. Use a rounded rectangle background, a stroked abstract
waveform path, and a restrained two-colour linear gradient. Preserve the
existing badge count cap of 99.

The icon must have a deliberate, fixed intrinsic size and use no text in the
unbadged state. It must remain readable in both light and dark menu-bar
appearances.

## Verification

- Add a focused unit test for the presentation model or source contract that
  verifies the branded mark and count accessibility label remain present.
- Build the release app and visually inspect the icon in the macOS menu bar
  with zero and nonzero actionable counts.
- Run the full Swift suite and both installer regression tests.

## Non-goals

- Do not redesign the popover, change badge-count logic, add animation, or
  alter notification behaviour in this change.
