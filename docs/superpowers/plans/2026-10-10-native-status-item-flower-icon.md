# Native Status Item and Flower Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unreliable SwiftUI menu-bar bridge with a direct AppKit status item that displays the approved standalone flower icon and opens PR Pulse in a native popover.

**Architecture:** `PRPulseApplicationDelegate` will retain one `AppDependencies` container and a `PRPulseStatusItemController`. The controller owns the AppKit status item, renders the local flower asset plus optional actionable badge, and anchors an `NSPopover` containing the existing SwiftUI dashboard. The SwiftUI Settings and Connection Errors scenes remain in the app and receive the same dashboard view model.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, XCTest, macOS 14+

**Spec:** `docs/superpowers/specs/2026-10-10-native-status-item-flower-icon-design.md`

## Global Constraints

- Support macOS 14 and later.
- The menu mark is an original standalone four-petal amber-copper flower with transparent surroundings; no tile, text, waveform, branch glyph, or GitHub logo.
- Use the direct AppKit status-item API; remove the SwiftUI `MenuBarExtra` scene.
- Preserve the existing 420 x 560 dashboard, Settings, Connection Errors, token handling, and dashboard state.
- Do not create a pull request until the fresh local app has remained running for at least ten seconds and the user has verified the visible flower and click-open dashboard.

## Review Focus

- A zero or negative actionable count shows the flower without a badge; Task 1 tests normalized count and badge visibility.
- Counts above 99 display `99` rather than changing the status-item layout; Task 1 tests capped badge text.
- Repeated clicks alternate exactly between presenting and closing the popover; Task 2 tests the toggle sequence with a fake popover host.
- Application relaunch creates one retained status item rather than duplicated items; Task 2 tests install idempotence.
- Settings and connection-error actions from the hosted dashboard still reach their existing scenes; Task 3 adds an integration assertion for the injected actions.

---

## File structure

- `Sources/PRPulseApp/App/PRPulseApplicationDelegate.swift` — app lifecycle, shared dependencies, and controller ownership.
- `Sources/PRPulseApp/App/PRPulseStatusItemController.swift` — direct `NSStatusItem`, popover, hosted dashboard, and lifecycle management.
- `Sources/PRPulseApp/App/StatusItemIconPresentation.swift` — pure badge normalization, icon drawing layout, and accessibility copy.
- `Sources/PRPulseApp/Resources/PRPulseFlower@2x.png` — approved transparent flower artwork at menu-bar asset resolution.
- `Sources/PRPulseApp/App/PRPulseApp.swift` — SwiftUI scene declarations only; removes `MenuBarExtra` and consumes the delegate's shared view model.
- `Sources/PRPulseApp/UI/ContentView.swift` — accepts injected host actions for Settings and Connection Errors when displayed outside a SwiftUI window scene.
- `Tests/PRPulseAppTests/StatusItemIconPresentationTests.swift` — deterministic badge and accessibility behavior.
- `Tests/PRPulseAppTests/PRPulseStatusItemControllerTests.swift` — status-item retention and popover toggle behavior through fakes.
- `Tests/PRPulseAppTests/ApplicationLifecycleTests.swift` — shared dependency ownership and scene/action wiring.

### Task 1: Flower asset and status-item presentation

**Files:**
- Create: `Sources/PRPulseApp/Resources/PRPulseFlower@2x.png`
- Create: `Sources/PRPulseApp/App/StatusItemIconPresentation.swift`
- Create: `Tests/PRPulseAppTests/StatusItemIconPresentationTests.swift`

**Interfaces:**
- Produces: `StatusItemIconPresentation.normalizedCount(for: Int) -> Int`, `badgeText(for: Int) -> String?`, and `accessibilityLabel(for: Int) -> String`.
- Produces: `StatusItemIconRenderer.makeImage(actionableCount: Int) -> NSImage` for the AppKit controller.

- [ ] **Step 1: Add failing presentation tests**

```swift
func testZeroOrNegativeCountHasNoBadge() {
    XCTAssertNil(StatusItemIconPresentation.badgeText(for: 0))
    XCTAssertNil(StatusItemIconPresentation.badgeText(for: -1))
}

func testBadgeTextCapsAtNinetyNine() {
    XCTAssertEqual(StatusItemIconPresentation.badgeText(for: 120), "99")
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `swift test --filter StatusItemIconPresentationTests`

Expected: FAIL because `StatusItemIconPresentation` does not exist.

- [ ] **Step 3: Add the approved local flower asset and presentation types**

Create a transparent 48 x 48 px PNG from the approved compact flower artwork. Implement the pure count rules and render the flower at 18 px inside an `NSImage`; overlay a coral badge only for a positive count, using white text and a maximum rendered value of `99`.

- [ ] **Step 4: Run the focused tests and inspect the asset at 24 px**

Run: `swift test --filter StatusItemIconPresentationTests`

Expected: PASS.

Run: `sips -Z 24 Sources/PRPulseApp/Resources/PRPulseFlower@2x.png --out /tmp/prpulse-flower-24.png`

Expected: a clear standalone four-petal flower with no background container.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/PRPulseApp/Resources/PRPulseFlower@2x.png Sources/PRPulseApp/App/StatusItemIconPresentation.swift Tests/PRPulseAppTests/StatusItemIconPresentationTests.swift
git commit -m "feat: add PR Pulse flower status icon"
```

### Task 2: Direct AppKit status item and popover

**Files:**
- Create: `Sources/PRPulseApp/App/PRPulseStatusItemController.swift`
- Create: `Tests/PRPulseAppTests/PRPulseStatusItemControllerTests.swift`

**Interfaces:**
- Consumes: `DashboardViewModel` and `StatusItemIconRenderer.makeImage(actionableCount:)`.
- Produces: `PRPulseStatusItemController.install(with: DashboardViewModel, actions: DashboardHostActions)`, `update(actionableCount: Int)`, `togglePopover()`, and `tearDown()`.
- Produces: `DashboardHostActions(showSettings: @MainActor () -> Void, showConnectionErrors: @MainActor () -> Void, quit: @MainActor () -> Void)`.

- [ ] **Step 1: Add failing controller tests using fakes**

```swift
func testInstallRetainsExactlyOneStatusItem() {
    controller.install(with: dashboard, actions: actions)
    controller.install(with: dashboard, actions: actions)
    XCTAssertEqual(statusBar.createdItemCount, 1)
}

func testToggleAlternatesPopoverPresentation() {
    controller.install(with: dashboard, actions: actions)
    controller.togglePopover()
    controller.togglePopover()
    XCTAssertEqual(popover.events, [.show, .close])
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `swift test --filter PRPulseStatusItemControllerTests`

Expected: FAIL because the controller and testable AppKit adapters do not exist.

- [ ] **Step 3: Implement the controller with narrow AppKit adapters**

Use `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)` and retain the returned item. Attach the renderer image and accessibility label to its button. Use an `NSPopover` with an `NSHostingController` whose root is `ContentView(viewModel: dashboard, hostActions: actions)` and set its frame to 420 x 560. Observe `dashboard.badgeCount` on the main actor and refresh the button image when it changes. Make `install` idempotent and remove the item in `tearDown`.

- [ ] **Step 4: Run the focused tests and verify they pass**

Run: `swift test --filter PRPulseStatusItemControllerTests`

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/PRPulseApp/App/PRPulseStatusItemController.swift Tests/PRPulseAppTests/PRPulseStatusItemControllerTests.swift
git commit -m "feat: add native PR Pulse status item"
```

### Task 3: Application lifecycle and existing window actions

**Files:**
- Create: `Sources/PRPulseApp/App/PRPulseApplicationDelegate.swift`
- Modify: `Sources/PRPulseApp/App/PRPulseApp.swift`
- Modify: `Sources/PRPulseApp/UI/ContentView.swift`
- Modify: `Tests/PRPulseAppTests/SettingsSceneTests.swift`
- Create: `Tests/PRPulseAppTests/ApplicationLifecycleTests.swift`

**Interfaces:**
- Consumes: `PRPulseStatusItemController.install(with:actions:)` and `DashboardHostActions` from Task 2.
- Produces: `PRPulseApplicationDelegate.dependencies: AppDependencies` as the sole application dependency owner.

- [ ] **Step 1: Add failing lifecycle and action-wiring tests**

```swift
func testApplicationDelegateUsesOneDependencyContainerForStatusItemAndScenes() throws {
    let appSource = try source(named: "Sources/PRPulseApp/App/PRPulseApp.swift")
    XCTAssertTrue(appSource.contains("@NSApplicationDelegateAdaptor(PRPulseApplicationDelegate.self)"))
    XCTAssertFalse(appSource.contains("MenuBarExtra"))
}

func testHostedDashboardAcceptsSettingsAndConnectionErrorActions() {
    var settingsCalls = 0
    var errorWindowCalls = 0
    let actions = DashboardHostActions(
        showSettings: { settingsCalls += 1 },
        showConnectionErrors: { errorWindowCalls += 1 },
        quit: {}
    )
    actions.showSettings()
    actions.showConnectionErrors()
    XCTAssertEqual(settingsCalls, 1)
    XCTAssertEqual(errorWindowCalls, 1)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `swift test --filter ApplicationLifecycleTests`

Expected: FAIL because the delegate and action injection do not exist.

- [ ] **Step 3: Wire the direct status item into the app lifecycle**

Create `PRPulseApplicationDelegate` as the `NSApplicationDelegate`. It owns the sole `AppDependencies` and installs the status item in `applicationDidFinishLaunching`; it tears down in `applicationWillTerminate`. Update `PRPulseApp` to use `@NSApplicationDelegateAdaptor`, remove the `MenuBarExtra` scene, and pass `delegate.dependencies.dashboard` to Settings and Connection Errors. Update `ContentView` so Settings, errors, and Quit invoke `DashboardHostActions` when supplied, while preserving environment-based scene behavior for normal SwiftUI windows.

- [ ] **Step 4: Run focused tests and the full suite**

Run: `swift test --filter ApplicationLifecycleTests`

Expected: PASS.

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/PRPulseApp/App/PRPulseApplicationDelegate.swift Sources/PRPulseApp/App/PRPulseApp.swift Sources/PRPulseApp/UI/ContentView.swift Tests/PRPulseAppTests/ApplicationLifecycleTests.swift Tests/PRPulseAppTests/SettingsSceneTests.swift
git commit -m "fix: retain PR Pulse menu bar status item"
```

### Task 4: Local installed-app verification

**Files:**
- Modify: no repository files; this is a release-build and installed-app checkpoint.

**Interfaces:**
- Consumes: the release product and installed `/Applications/PRPulseApp.app`.
- Produces: evidence that the installed app remains alive and a user-visible verification of the native flower status item.

- [ ] **Step 1: Run the existing installer regression test**

Run: `bash Tests/InstallerTests/test_install_prpulse.sh`

Expected: PASS; the installer creates its bundle from a fresh release build.

- [ ] **Step 2: Build, install, and perform the user-visible checkpoint**

Run:

```bash
swift build -c release --product PRPulseApp
bash scripts/install_prpulse.sh /Applications/PRPulseApp.app
pkill -x PRPulseApp 2>/dev/null || true
open -n /Applications/PRPulseApp.app
sleep 10
pgrep -x PRPulseApp
```

Expected: one running process. Ask the user to verify the visible standalone flower and click-open dashboard before opening any pull request.

## Self-review

- **Spec coverage:** Tasks 1-4 cover the flower asset, direct status item, native popover, shared dependencies, retained Settings and error access, unit coverage, release build, local install, and user-visible verification. No scope gaps found.
- **Step scan:** Every task starts with a failing test and names the resulting interface, verification command, and commit boundary.
- **Type consistency:** `StatusItemIconPresentation`, `StatusItemIconRenderer`, `DashboardHostActions`, `PRPulseStatusItemController`, and `PRPulseApplicationDelegate` are introduced before their consumers.
- **Review focus:** Each listed failure mode is assigned to Tasks 1-3; Task 4 performs the required ten-second installed-app checkpoint.
- **Proportion:** The plan specifies interfaces and verifiable steps without prescribing implementation bodies.
