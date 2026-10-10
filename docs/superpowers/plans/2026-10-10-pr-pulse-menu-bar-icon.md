# PR Pulse Menu-Bar Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace PRPulse’s generic branch icon with a branded abstract pink-to-violet waveform that remains clear in the macOS menu bar.

**Architecture:** Keep `BadgeIcon` as the sole menu-bar presentation component. Replace its SF Symbol with a compact SwiftUI vector tile: rounded charcoal background, custom abstract waveform path, and a two-colour gradient. Preserve the existing count badge and accessibility label.

**Tech Stack:** Swift 6.2, SwiftUI `Path`, XCTest, macOS 14+.

---

### Task 1: Add a testable icon presentation contract

**Files:**
- Modify: `Sources/PRPulseApp/App/PRPulseApp.swift:32-52`
- Create: `Tests/PRPulseAppTests/BadgeIconTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PRPulseApp

final class BadgeIconTests: XCTestCase {
    func testAccessibleLabelIncludesActionableCount() {
        XCTAssertEqual(BadgeIconPresentation.accessibilityLabel(for: 3), "PRPulse 3 actionable")
    }

    func testBadgeCountIsCappedAtNinetyNine() {
        XCTAssertEqual(BadgeIconPresentation.badgeText(for: 124), "99")
    }
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter BadgeIconTests`

Expected: compilation failure because `BadgeIconPresentation` does not exist.

- [ ] **Step 3: Implement the minimal presentation helper**

```swift
enum BadgeIconPresentation {
    static func badgeText(for count: Int) -> String { "\(min(99, count))" }
    static func accessibilityLabel(for count: Int) -> String { "PRPulse \(count) actionable" }
}
```

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter BadgeIconTests`

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PRPulseApp/App/PRPulseApp.swift Tests/PRPulseAppTests/BadgeIconTests.swift && git commit -m "test: cover PR pulse badge presentation"
```

### Task 2: Render the abstract PR Pulse mark

**Files:**
- Modify: `Sources/PRPulseApp/App/PRPulseApp.swift:32-52`

- [ ] **Step 1: Replace the SF Symbol with a vector tile**

Add a private `PRPulseWaveformMark` view that renders a charcoal `RoundedRectangle`
and a stroked `Path` with rounded peaks and valleys. Use a `LinearGradient` from
pink to violet for the waveform. The mark must use a fixed compact frame and no
text when there is no actionable count.

```swift
Path { path in
    path.move(to: CGPoint(x: 3, y: 12))
    path.addCurve(to: CGPoint(x: 10, y: 6), control1: CGPoint(x: 5, y: 12), control2: CGPoint(x: 7, y: 6))
    path.addCurve(to: CGPoint(x: 16, y: 18), control1: CGPoint(x: 12, y: 6), control2: CGPoint(x: 14, y: 18))
    path.addCurve(to: CGPoint(x: 23, y: 10), control1: CGPoint(x: 18, y: 18), control2: CGPoint(x: 20, y: 10))
}
.stroke(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
```

- [ ] **Step 2: Retain the existing actionable badge behavior**

Use `BadgeIconPresentation.badgeText(for:)` for a coral capsule when `badgeCount > 0`.
The badge remains top trailing and the accessibility label uses
`BadgeIconPresentation.accessibilityLabel(for:)`.

- [ ] **Step 3: Verify build and focused tests**

Run: `swift build -c release --product PRPulseApp && swift test --filter BadgeIconTests`

Expected: release build succeeds and both focused tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/PRPulseApp/App/PRPulseApp.swift && git commit -m "feat: add abstract PR pulse menu icon"
```

### Task 3: Verify the local app build

**Files:**
- No source changes expected.

- [ ] **Step 1: Run regression checks**

Run: `swift test && bash Tests/InstallerTests/test_install_prpulse.sh && bash Tests/InstallerTests/test_install_latest_release.sh && git diff --check`

Expected: Swift tests and both installer tests pass; whitespace check is clean.

- [ ] **Step 2: Build and install the local app**

Run: `bash scripts/install_prpulse.sh /Applications/PRPulseApp.app`

Expected: the script reports a release build and creates the application bundle.

- [ ] **Step 3: Manual acceptance**

Open `/Applications/PRPulseApp.app` and inspect the menu bar in light and dark
appearance. Confirm the mark is a dark rounded tile with an abstract pink-to-
violet waveform, the zero-count state has no text, and the actionable-count
badge remains readable.
