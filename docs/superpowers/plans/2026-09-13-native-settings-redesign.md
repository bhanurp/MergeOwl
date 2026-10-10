# Native Settings Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Settings open reliably from the menu-bar app and replace the long form with a polished native macOS preferences window.

**Architecture:** `PRPulseApp` owns SwiftUI’s `Settings` scene instead of a custom `Window`; the menu-bar view calls the native settings presentation action. A focused settings shell owns sidebar selection, while existing settings, Keychain storage, and dashboard operations remain the source of truth.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, XCTest, macOS 13+.

---

## File structure

- Create `Sources/PRPulseApp/UI/Settings/SettingsPane.swift` — sidebar destinations.
- Create `Sources/PRPulseApp/UI/Settings/SettingsShellView.swift` — sidebar and pane composition.
- Create `Sources/PRPulseApp/UI/Settings/AccountSettingsView.swift` — token setup and connection feedback.
- Create `Sources/PRPulseApp/UI/Settings/GeneralSettingsViews.swift` — the four remaining panes.
- Modify `Sources/PRPulseApp/App/PRPulseApp.swift` and `Sources/PRPulseApp/UI/ContentView.swift` — native scene and trigger.
- Delete `Sources/PRPulseApp/App/SettingsWindowPresenter.swift` and `Sources/PRPulseApp/UI/SettingsView.swift` — obsolete workaround/form.
- Create settings model and account state XCTest coverage; delete presenter coverage.

### Task 1: Define the sidebar model

**Files:**
- Create: `Sources/PRPulseApp/UI/Settings/SettingsPane.swift`
- Test: `Tests/PRPulseAppTests/SettingsPaneTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testAccountIsDefaultAndPanesAreInProductOrder() {
    XCTAssertEqual(SettingsPane.defaultPane, .account)
    XCTAssertEqual(SettingsPane.allCases, [.account, .refresh, .notifications, .repositories, .advanced])
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter SettingsPaneTests`

Expected: compile failure because `SettingsPane` is absent.

- [ ] **Step 3: Implement the minimal model**

```swift
enum SettingsPane: String, CaseIterable, Identifiable {
    case account = "Account", refresh = "Refresh", notifications = "Notifications"
    case repositories = "Repositories", advanced = "Advanced"
    static let defaultPane: SettingsPane = .account
    var id: Self { self }
    var symbolName: String {
        switch self {
        case .account: "person.crop.circle"
        case .refresh: "arrow.clockwise"
        case .notifications: "bell"
        case .repositories: "folder"
        case .advanced: "slider.horizontal.3"
        }
    }
}
```

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter SettingsPaneTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PRPulseApp/UI/Settings/SettingsPane.swift Tests/PRPulseAppTests/SettingsPaneTests.swift && git commit -m "feat: add settings sidebar model"
```

### Task 2: Model account feedback before rendering it

**Files:**
- Create: `Sources/PRPulseApp/UI/Settings/AccountSettingsView.swift`
- Test: `Tests/PRPulseAppTests/AccountConnectionStateTests.swift`

- [ ] **Step 1: Write failing state tests**

```swift
func testConnectedAccountExplainsKeychainStorage() {
    let state = AccountConnectionState.connected(login: "octocat")
    XCTAssertEqual(state.title, "Connected as octocat")
    XCTAssertEqual(state.detail, "Your token is stored securely in Keychain.")
}

func testFailedAccountPreservesRecoveryMessage() {
    XCTAssertEqual(AccountConnectionState.failed("Invalid token").detail, "Invalid token")
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter AccountConnectionStateTests`

Expected: compile failure because `AccountConnectionState` is absent.

- [ ] **Step 3: Implement state and account pane**

Create states `disconnected`, `testing`, `connected(login:)`, and `failed(_)`, each
with title, detail, icon, and semantic color. Build a grouped account pane with
a masked `SecureField`, Connect/Update, Test connection, and destructive Remove
actions. Reuse existing Keychain and GitHub validation behavior; blank the field
after save, validate without logging tokens, and use `confirmationDialog` before
removing the Keychain item.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter AccountConnectionStateTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PRPulseApp/UI/Settings/AccountSettingsView.swift Tests/PRPulseAppTests/AccountConnectionStateTests.swift && git commit -m "feat: add GitHub account preferences pane"
```

### Task 3: Compose the native preferences window

**Files:**
- Create: `Sources/PRPulseApp/UI/Settings/SettingsShellView.swift`
- Create: `Sources/PRPulseApp/UI/Settings/GeneralSettingsViews.swift`

- [ ] **Step 1: Implement sidebar composition**

Use `NavigationSplitView` and `List(selection:)` from `SettingsPane.allCases`.
Initialize selection to `.defaultPane`; render `AccountSettingsView` and the four
remaining pane views using a `switch` in the detail column.

- [ ] **Step 2: Move existing controls to focused panes**

```swift
Toggle("Refresh on launch", isOn: Binding(
    get: { viewModel.settings.refreshOnLaunch },
    set: { viewModel.settings.refreshOnLaunch = $0 }
))
```

Keep the current refresh controls in Refresh; re-review/review-request/digest
controls in Notifications; watched-repository controls in Repositories; and test
notification, digest recompute, refresh, settings JSON, viewer copy, and log
export in Advanced. Add concise explanatory text and use `.formStyle(.grouped)`.

- [ ] **Step 3: Verify build**

Run: `swift build`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/PRPulseApp/UI/Settings/SettingsShellView.swift Sources/PRPulseApp/UI/Settings/GeneralSettingsViews.swift && git commit -m "feat: add native preferences sidebar"
```

### Task 4: Replace the fragile scene path

**Files:**
- Modify: `Sources/PRPulseApp/App/PRPulseApp.swift`
- Modify: `Sources/PRPulseApp/UI/ContentView.swift`
- Delete: `Sources/PRPulseApp/App/SettingsWindowPresenter.swift`
- Delete: `Sources/PRPulseApp/UI/SettingsView.swift`
- Delete: `Tests/PRPulseAppTests/SettingsWindowPresenterTests.swift`
- Create: `Tests/PRPulseAppTests/SettingsSceneTests.swift`

- [ ] **Step 1: Write the failing architecture regression test**

Load the application sources relative to `#filePath`, then assert:

```swift
XCTAssertTrue(appSource.contains("Settings {"))
XCTAssertTrue(contentSource.contains("@Environment(\\.openSettings)"))
XCTAssertFalse(contentSource.contains("openWindow(id: \"settings-window\")"))
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter SettingsSceneTests`

Expected: FAIL because the custom settings window and `openWindow` call exist.

- [ ] **Step 3: Implement native presentation**

Replace the custom Settings `Window` with:

```swift
Settings {
    SettingsShellView(viewModel: dependencies.dashboard)
        .frame(minWidth: 720, minHeight: 520)
}
```

Replace the gear handler with `@Environment(\.openSettings) private var
openSettings` and `openSettings()`. Retain `openWindow` only for Connection
Errors. Delete the presenter, old form, and presenter test.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter SettingsSceneTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "fix: present native settings from menu bar"
```

### Task 5: Verify the release candidate

**Files:**
- Modify: `README.md` only if account-setup wording needs correction.

- [ ] **Step 1: Run automated verification**

Run: `swift test && bash Tests/InstallerTests/test_install_latest_release.sh && git diff --check`

Expected: XCTest and installer regression pass; no whitespace errors.

- [ ] **Step 2: Build the distributable app**

Run: `bash scripts/build_app.sh`

Expected: `PRPulseApp.app` builds successfully.

- [ ] **Step 3: Perform manual acceptance**

Launch the app; verify the gear and Command-comma show one preferences window;
verify Account is selected by default; visit all five panes; confirm a saved token
never appears in UI, logs, or diagnostics.

- [ ] **Step 4: Commit any documentation adjustment**

```bash
git add README.md && git commit -m "docs: describe native preferences setup"
```
