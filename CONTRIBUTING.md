# Contributing to MergeOwl

Thanks for helping improve MergeOwl.

## Local setup

1. Install Xcode or a Swift toolchain compatible with Swift 6.2, then select Xcode with `xcode-select`.
2. Clone the repository and change into it.
3. Run `swift test`.
4. Run `swift build -c release --product MergeOwl`.

The executable product is MergeOwl. The internal `PRPulseApp` Swift target and existing storage, bundle and Keychain identifiers are intentionally retained for compatibility; a cosmetic rename must not reset users' profiles or credentials. Package resources include the approved transparent owl and a Finder ICNS built by `swift scripts/make_app_icon.swift` followed by `iconutil`.

## Pull requests

- Keep each pull request focused on one user problem.
- Add or update XCTest coverage for behavior changes.
- Update the README or changelog when a user-visible behavior changes.
- Before requesting review, run `swift test` and include the result in the pull-request description.

## Reporting bugs and proposing features

Open a GitHub issue. Describe the workflow you were trying to complete, not only the implementation you expect.
