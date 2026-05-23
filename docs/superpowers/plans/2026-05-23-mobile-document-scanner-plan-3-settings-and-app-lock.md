# Mobile Document Scanner — Plan 3: Settings + App Lock + Privacy Blur

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Settings screen with an optional Face ID app lock. When the lock is on, the library hides behind a lock screen on cold launch and again after the app has been in the background for >30 seconds. Independently of the lock state, the app's content gets blurred whenever the app is in the background so document names and thumbnails don't appear in the iOS app-switcher snapshot.

**Architecture:** A single `@Observable @MainActor` class (`AppLockSettings`) owns the persistent toggle (`@AppStorage`), the in-memory locked/unlocked state, and the background-timestamp logic. A `LockGate` view wraps the library and shows a lock screen with a Face ID prompt button when state says "locked." A separate `PrivacyBlurOverlay` covers the content whenever scene phase is anything other than `.active`. A `SettingsView` pushed from a new gear-icon nav-bar button hosts the App Lock toggle and an About row.

**Tech Stack:** SwiftUI, `LocalAuthentication` (`LAContext.evaluatePolicy(.deviceOwnerAuthentication)`), Foundation `@AppStorage`, `Bundle` for version info.

**Spec:** [`docs/superpowers/specs/2026-05-21-mobile-document-scanner-design.md`](../specs/2026-05-21-mobile-document-scanner-design.md) — Privacy lock and Settings sections.

**Prerequisite plans:** [Plan 1](2026-05-21-mobile-document-scanner-plan-1-foundation.md), [Plan 2a](2026-05-22-mobile-document-scanner-plan-2a-viewer-and-page-ops.md), [Plan 2b](2026-05-23-mobile-document-scanner-plan-2b-per-page-editor.md) all completed and verified on device.

---

## A note for the first-time iOS developer

Two new iOS idioms in this plan:

- **`LocalAuthentication`.** `LAContext` is Apple's biometric auth wrapper. `evaluatePolicy(.deviceOwnerAuthentication)` shows the system Face ID prompt and automatically falls back to device passcode if biometrics fail 3× or aren't enrolled. It runs async and resolves to a Bool + error. We never see the user's biometrics — just success/failure.
- **`@Environment(\.scenePhase)`.** SwiftUI's lifecycle observer. Fires when the app goes `.active → .inactive → .background` (and back). Use `.onChange(of: scenePhase)` to react. The transition through `.inactive` happens just before iOS takes the app-switcher screenshot — perfect timing to flip on a blur overlay.

A subtle thing: `LockGate` and `PrivacyBlurOverlay` look similar but solve different problems. LockGate hides content when the user must re-authenticate (auth-gated, has a button). PrivacyBlurOverlay covers content whenever the app isn't foregrounded (lifecycle-gated, no interaction). The blur covers a *gap* — the moment after iOS asks to snapshot the screen but before our lock gate has re-engaged. Both can be active at once.

## File structure (target end-state of Plan 3)

```text
DocumentScanner/
  Settings/                                 # NEW module
    AppLockSettings.swift                   # @AppStorage + LAContext + lock-state state machine
    SettingsView.swift                      # the settings screen
    AboutRow.swift                          # small reusable row for the version info
  App/
    DocumentScannerApp.swift                # MODIFY: wire LockGate + PrivacyBlurOverlay around LibraryView
    LockGate.swift                          # NEW: the auth-gated wrapper view
    PrivacyBlurOverlay.swift                # NEW: the lifecycle-gated blur
  Library/
    LibraryView.swift                       # MODIFY: add gear-icon top-left button → Settings
DocumentScannerTests/
  AppLockSettingsTests.swift                # NEW: state-machine logic (timestamp checks, toggle behavior)
```

After Plan 3:

- Tap gear in the library → Settings pushes onto the nav stack.
- Toggle "App Lock" → Face ID prompt → on success, the toggle flips.
- Quit/relaunch the app with lock on → lock screen with Face ID button on top of the library; tap Unlock → Face ID → library appears.
- Send app to background, wait 30s, return → lock re-engages.
- Send app to background for <30s → no re-lock (avoids friction when switching to Files.app and back).
- Open the app switcher (swipe up partially or double-press home) → the app's tile is blurred regardless of lock state.

---

## Task 1: AppLockSettings — the lock state machine

**Files:**
- Create: `DocumentScanner/DocumentScanner/Settings/AppLockSettings.swift`
- Create: `DocumentScanner/DocumentScannerTests/AppLockSettingsTests.swift`

A single `@MainActor @Observable` class owning:

- `isEnabled: Bool` (persistent via `@AppStorage`)
- `isLocked: Bool` (in-memory; true when the user must re-authenticate)
- `recordedBackgroundedAt: Date?` (in-memory; set when scene goes inactive/background)
- `shouldRelock(now:)` (pure function from state — returns true if lock is enabled AND we've been backgrounded longer than the 30s threshold)
- `authenticate() async -> Bool` (calls LAContext)

The class doesn't drive the lock screen itself — `LockGate` does that, by reading `isLocked` and calling `authenticate()` when the user taps Unlock.

Follow TDD for the pure logic. The LAContext call is a hardware call and not unit-testable.

- [ ] **Step 1: Write the failing tests**

  Create `DocumentScanner/DocumentScannerTests/AppLockSettingsTests.swift`:

  ```swift
  import XCTest
  @testable import DocumentScanner

  @MainActor
  final class AppLockSettingsTests: XCTestCase {

      func test_shouldRelock_falseWhenLockDisabled() {
          let settings = AppLockSettings(isEnabled: false, backgroundedAt: Date().addingTimeInterval(-9999))
          XCTAssertFalse(settings.shouldRelock(now: Date()))
      }

      func test_shouldRelock_falseWhenNeverBackgrounded() {
          let settings = AppLockSettings(isEnabled: true, backgroundedAt: nil)
          XCTAssertFalse(settings.shouldRelock(now: Date()))
      }

      func test_shouldRelock_falseWhenBackgroundedRecently() {
          let now = Date()
          let settings = AppLockSettings(isEnabled: true, backgroundedAt: now.addingTimeInterval(-10))
          XCTAssertFalse(settings.shouldRelock(now: now))
      }

      func test_shouldRelock_trueWhenBackgroundedLongerThanThreshold() {
          let now = Date()
          let settings = AppLockSettings(isEnabled: true, backgroundedAt: now.addingTimeInterval(-31))
          XCTAssertTrue(settings.shouldRelock(now: now))
      }

      func test_recordBackground_setsTimestamp() {
          let settings = AppLockSettings(isEnabled: true, backgroundedAt: nil)
          let before = Date()
          settings.recordBackground()
          XCTAssertNotNil(settings.recordedBackgroundedAt)
          XCTAssertGreaterThanOrEqual(settings.recordedBackgroundedAt!, before)
      }

      func test_clearBackground_nilsTimestamp() {
          let settings = AppLockSettings(isEnabled: true, backgroundedAt: Date())
          settings.clearBackground()
          XCTAssertNil(settings.recordedBackgroundedAt)
      }

      func test_lock_setsLocked() {
          let settings = AppLockSettings(isEnabled: true, backgroundedAt: nil)
          settings.lock()
          XCTAssertTrue(settings.isLocked)
      }

      func test_unlock_clearsLocked() {
          let settings = AppLockSettings(isEnabled: true, backgroundedAt: nil)
          settings.lock()
          settings.unlock()
          XCTAssertFalse(settings.isLocked)
      }
  }
  ```

- [ ] **Step 2: Run, see failure**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner/DocumentScanner
  xcodebuild test -scheme DocumentScanner -destination 'id=B762C669-0A64-4665-8C00-10BD6628CBA2' -only-testing:DocumentScannerTests/AppLockSettingsTests 2>&1 | tail -10
  ```

- [ ] **Step 3: Implement `AppLockSettings`**

  ```swift
  import Foundation
  import Observation
  import LocalAuthentication

  @MainActor
  @Observable
  final class AppLockSettings {

      /// Threshold beyond which a foreground return re-engages the lock.
      static let backgroundThreshold: TimeInterval = 30

      /// User-facing persistent toggle.
      var isEnabled: Bool {
          didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
      }

      /// In-memory: true when the lock UI is showing.
      private(set) var isLocked: Bool

      /// In-memory: timestamp of the last scene-deactivation. nil when foregrounded.
      private(set) var recordedBackgroundedAt: Date?

      private static let enabledKey = "AppLockSettings.isEnabled"

      /// Production initializer reads persisted state. Tests use the throws-everything-in
      /// designated initializer below.
      convenience init() {
          let stored = UserDefaults.standard.bool(forKey: Self.enabledKey)
          self.init(isEnabled: stored, backgroundedAt: nil)
      }

      init(isEnabled: Bool, backgroundedAt: Date?) {
          self.isEnabled = isEnabled
          self.recordedBackgroundedAt = backgroundedAt
          // Cold launch starts in the locked state if enabled; LockGate triggers
          // auth on appear and unlocks on success.
          self.isLocked = isEnabled
      }

      // MARK: - State transitions

      func lock() { isLocked = true }
      func unlock() { isLocked = false }
      func recordBackground() { recordedBackgroundedAt = Date() }
      func clearBackground() { recordedBackgroundedAt = nil }

      /// Returns true if we should re-engage the lock on foregrounding.
      /// Pure function of current state; safe to call repeatedly.
      func shouldRelock(now: Date = Date()) -> Bool {
          guard isEnabled, let backgroundedAt = recordedBackgroundedAt else { return false }
          return now.timeIntervalSince(backgroundedAt) > Self.backgroundThreshold
      }

      // MARK: - LocalAuthentication (not unit-tested — hardware call)

      /// Show the system Face ID / passcode prompt and return whether it succeeded.
      func authenticate(reason: String) async -> Bool {
          let context = LAContext()
          var error: NSError?
          guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
              // No biometrics + no passcode set, or some other config error.
              return false
          }
          do {
              return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
          } catch {
              return false
          }
      }
  }
  ```

- [ ] **Step 4: Run tests, all 8 pass**

- [ ] **Step 5: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/Settings/AppLockSettings.swift DocumentScanner/DocumentScannerTests/AppLockSettingsTests.swift
  git status
  git commit -m "Add AppLockSettings: state machine for optional Face ID lock

  Task 1 of plan-3: @Observable @MainActor class that owns the
  persistent isEnabled toggle (@AppStorage-backed via UserDefaults),
  the in-memory isLocked state, and the recordedBackgroundedAt
  timestamp used by shouldRelock(now:) to decide whether a return
  from background should re-engage the lock (>30s threshold).
  LAContext authenticate(reason:) wraps Face ID / passcode prompt
  with a graceful canEvaluatePolicy fallback.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 2: PrivacyBlurOverlay — lifecycle-gated blur

**Files:**
- Create: `DocumentScanner/DocumentScanner/App/PrivacyBlurOverlay.swift`

A small view that covers its content with an opaque background + blur whenever the scene phase is not `.active`. Runs independently of the lock — applies even with the lock off, because we don't want document names appearing in the iOS app-switcher snapshot.

No unit tests — pure SwiftUI lifecycle reaction. Verified in device smoke test.

- [ ] **Step 1: Implement**

  ```swift
  import SwiftUI

  /// Covers content with a system material blur whenever the scene is not
  /// `.active`. Used to redact document names and thumbnails from the iOS
  /// app-switcher snapshot, independently of the App Lock state.
  struct PrivacyBlurOverlay<Content: View>: View {
      @ViewBuilder let content: () -> Content
      @Environment(\.scenePhase) private var scenePhase

      var body: some View {
          ZStack {
              content()
              if scenePhase != .active {
                  // Opaque material so the underlying content is fully hidden,
                  // not just softened.
                  Rectangle()
                      .fill(.regularMaterial)
                      .ignoresSafeArea()
                      .overlay {
                          Image(systemName: "doc.viewfinder")
                              .font(.system(size: 64))
                              .foregroundStyle(.secondary)
                      }
              }
          }
      }
  }
  ```

- [ ] **Step 2: Build**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner/DocumentScanner
  xcodebuild build -scheme DocumentScanner -destination 'id=B762C669-0A64-4665-8C00-10BD6628CBA2' 2>&1 | grep -E "warning:|error:|BUILD (SUCCEEDED|FAILED)" | grep -v "^ld:\|appintentsmetadataprocessor" | head -10
  ```

- [ ] **Step 3: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/App/PrivacyBlurOverlay.swift
  git commit -m "Add PrivacyBlurOverlay covering content on background

  Task 2 of plan-3: ZStack wrapper that renders the wrapped content
  with an opaque material blur whenever scenePhase != .active. Keeps
  document names and thumbnails out of the iOS app-switcher snapshot
  regardless of whether the App Lock is enabled.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 3: LockGate — auth-gated wrapper

**Files:**
- Create: `DocumentScanner/DocumentScanner/App/LockGate.swift`

The lock screen view. When `lockSettings.isLocked` is true, shows an opaque overlay with a "Mobile Scanner is locked" message and an "Unlock with Face ID" button. Tapping the button calls `lockSettings.authenticate(reason:)` and, on success, calls `unlock()`.

On scene phase transitions:
- `.inactive` or `.background` → call `lockSettings.recordBackground()`
- back to `.active` → if `shouldRelock()` returns true, call `lock()`; otherwise clear the timestamp

On `.onAppear` for a cold launch with `isLocked` already true (set by `AppLockSettings.init`), prompt Face ID immediately so the user isn't forced to tap the button manually.

- [ ] **Step 1: Implement**

  ```swift
  import SwiftUI

  /// Wraps content in an auth-gated screen. When the lock is active, shows
  /// an opaque lock UI; when not, shows the content. Reacts to scene-phase
  /// changes to re-lock after >30s in background.
  struct LockGate<Content: View>: View {
      @Bindable var lockSettings: AppLockSettings
      @ViewBuilder let content: () -> Content
      @Environment(\.scenePhase) private var scenePhase

      var body: some View {
          ZStack {
              content()
              if lockSettings.isLocked {
                  lockScreen
              }
          }
          .onChange(of: scenePhase) { _, newPhase in
              switch newPhase {
              case .active:
                  if lockSettings.shouldRelock() {
                      lockSettings.lock()
                  }
                  lockSettings.clearBackground()
              case .inactive, .background:
                  lockSettings.recordBackground()
              @unknown default:
                  break
              }
          }
          .task(id: lockSettings.isLocked) {
              // Auto-prompt on cold launch (isLocked started true) and any
              // explicit relock that doesn't already have an auth in flight.
              if lockSettings.isLocked {
                  let ok = await lockSettings.authenticate(reason: "Unlock your document library")
                  if ok { lockSettings.unlock() }
              }
          }
      }

      private var lockScreen: some View {
          ZStack {
              Color(.systemBackground).ignoresSafeArea()
              VStack(spacing: 24) {
                  Image(systemName: "lock.fill")
                      .font(.system(size: 72))
                      .foregroundStyle(.tint)
                  Text("Mobile Scanner is locked")
                      .font(.title2.weight(.semibold))
                  Button("Unlock with Face ID") {
                      Task {
                          let ok = await lockSettings.authenticate(reason: "Unlock your document library")
                          if ok { lockSettings.unlock() }
                      }
                  }
                  .buttonStyle(.borderedProminent)
                  .controlSize(.large)
              }
          }
      }
  }
  ```

- [ ] **Step 2: Build**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner/DocumentScanner
  xcodebuild build -scheme DocumentScanner -destination 'id=B762C669-0A64-4665-8C00-10BD6628CBA2' 2>&1 | grep -E "warning:|error:|BUILD (SUCCEEDED|FAILED)" | grep -v "^ld:\|appintentsmetadataprocessor" | head -10
  ```

- [ ] **Step 3: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/App/LockGate.swift
  git commit -m "Add LockGate: auth-gated wrapper over content

  Task 3 of plan-3: shows a lock screen with a Face ID button when
  AppLockSettings.isLocked is true. Auto-prompts Face ID on cold
  launch via .task(id:). Reacts to scene-phase changes: records
  the background timestamp on .inactive/.background and decides
  whether to re-lock on return to .active using
  AppLockSettings.shouldRelock().

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 4: SettingsView — the screen + About row

**Files:**
- Create: `DocumentScanner/DocumentScanner/Settings/SettingsView.swift`
- Create: `DocumentScanner/DocumentScanner/Settings/AboutRow.swift`

Two rows for v1:

1. **App Lock** — a `Toggle` bound to `lockSettings.isEnabled`. On change, prompt Face ID; on success, accept the new value. On failure, revert.
2. **About** — shows app name + version (`CFBundleShortVersionString`) + build (`CFBundleVersion`).

- [ ] **Step 1: Implement `AboutRow`**

  ```swift
  import SwiftUI

  struct AboutRow: View {
      var body: some View {
          HStack {
              Text("Version")
              Spacer()
              Text(versionString)
                  .foregroundStyle(.secondary)
                  .monospacedDigit()
          }
      }

      private var versionString: String {
          let info = Bundle.main.infoDictionary ?? [:]
          let short = info["CFBundleShortVersionString"] as? String ?? "?"
          let build = info["CFBundleVersion"] as? String ?? "?"
          return "\(short) (\(build))"
      }
  }
  ```

- [ ] **Step 2: Implement `SettingsView`**

  ```swift
  import SwiftUI

  struct SettingsView: View {
      @Bindable var lockSettings: AppLockSettings
      @State private var authError: String?

      var body: some View {
          Form {
              Section("Privacy") {
                  Toggle("App Lock", isOn: Binding(
                      get: { lockSettings.isEnabled },
                      set: { newValue in Task { await toggleLock(to: newValue) } }
                  ))
                  if let authError {
                      Text(authError).font(.footnote).foregroundStyle(.red)
                  }
              }
              Section("About") {
                  AboutRow()
              }
          }
          .navigationTitle("Settings")
          .navigationBarTitleDisplayMode(.inline)
      }

      /// Toggle the lock setting — but require successful auth before applying.
      /// Spec: "Enabling and disabling the lock both require successful
      /// authentication first."
      private func toggleLock(to newValue: Bool) async {
          let reason = newValue
              ? "Enable App Lock for your document library"
              : "Disable App Lock for your document library"
          let ok = await lockSettings.authenticate(reason: reason)
          if ok {
              lockSettings.isEnabled = newValue
              authError = nil
          } else {
              authError = "Face ID failed. Try again."
              // No need to manually revert — the Toggle binding's `get` still
              // reads the unchanged isEnabled.
          }
      }
  }
  ```

- [ ] **Step 3: Build**

- [ ] **Step 4: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/Settings/SettingsView.swift DocumentScanner/DocumentScanner/Settings/AboutRow.swift
  git commit -m "Add SettingsView + AboutRow

  Task 4 of plan-3: Form-style Settings screen with two rows. App
  Lock toggle requires successful Face ID auth before applying the
  new value (in either direction, per spec). About row shows app
  version + build from Info.plist.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 5: Wire LockGate + PrivacyBlur + gear icon

**Files:**
- Modify: `DocumentScanner/DocumentScanner/App/DocumentScannerApp.swift`
- Modify: `DocumentScanner/DocumentScanner/Library/LibraryView.swift`

Wrap the library scene in `LockGate(lockSettings:) { PrivacyBlurOverlay { LibraryView(...) } }`. Construct one `AppLockSettings` at the app level and pass it down to `LibraryView` so the gear icon's NavigationLink can hand it off to `SettingsView`.

- [ ] **Step 1: Update `DocumentScannerApp.swift`**

  ```swift
  import SwiftUI

  @main
  struct DocumentScannerApp: App {
      @State private var store = MetadataQueryLibraryStore()
      @State private var lockSettings = AppLockSettings()

      private let container = ICloudContainer()
      private let pipeline = ScanPipeline()
      private let scannerPresenter: DocumentScannerPresenting = SystemDocumentScanner()

      var body: some Scene {
          WindowGroup {
              LockGate(lockSettings: lockSettings) {
                  PrivacyBlurOverlay {
                      LibraryView(
                          store: store,
                          scannerPresenter: scannerPresenter,
                          storage: DocumentStorage(documentsURL: container.resolveDocumentsURL()),
                          pipeline: pipeline,
                          lockSettings: lockSettings
                      )
                  }
              }
          }
      }
  }
  ```

- [ ] **Step 2: Add gear icon + lockSettings property to `LibraryView`**

  In `DocumentScanner/DocumentScanner/Library/LibraryView.swift`:

  (a) Add a new `let` property near the others:

  ```swift
  let lockSettings: AppLockSettings
  ```

  (b) In the `.toolbar` block, add a `ToolbarItem(placement: .topBarLeading)` ahead of the existing trailing + button:

  ```swift
  ToolbarItem(placement: .topBarLeading) {
      NavigationLink {
          SettingsView(lockSettings: lockSettings)
      } label: {
          Image(systemName: "gearshape")
      }
  }
  ```

  Keep the existing `.topBarTrailing` "+" button as-is.

- [ ] **Step 3: Build**

- [ ] **Step 4: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/App/DocumentScannerApp.swift DocumentScanner/DocumentScanner/Library/LibraryView.swift
  git commit -m "Wire LockGate, PrivacyBlurOverlay, and gear icon

  Task 5 of plan-3: app root wraps the library in
  LockGate(lockSettings:) → PrivacyBlurOverlay → LibraryView, where
  the lock state machine + the lifecycle-gated blur live above the
  navigation stack. LibraryView gets a topBarLeading gear icon that
  pushes SettingsView onto the same NavigationStack as the document
  rows.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 6: Device smoke test

- [ ] **Step 1: Cmd+R to a real iPhone**

- [ ] **Step 2: Verify gear icon and Settings**

  - Library shows a gear icon top-left.
  - Tap gear → Settings pushes onto the stack.
  - Two sections: **Privacy** (App Lock toggle, off by default) and **About** (Version row).

- [ ] **Step 3: Test the App Lock toggle**

  - Tap the toggle → Face ID prompt appears with reason "Enable App Lock for your document library".
  - Authenticate → toggle flips on. No error text.
  - Tap toggle again → Face ID prompt appears with the disable-reason text.
  - Cancel the Face ID prompt → red error text appears: "Face ID failed. Try again." Toggle stays on.
  - Tap toggle again → authenticate → toggle flips off.

- [ ] **Step 4: Test cold-launch lock**

  - Toggle App Lock on.
  - Force-quit the app (swipe up from bottom, swipe its card up).
  - Re-launch from home screen → lock screen appears immediately with the lock icon, "Mobile Scanner is locked", and an "Unlock with Face ID" button.
  - Face ID prompt should have auto-appeared on launch.
  - Authenticate → library appears.
  - Cancel the Face ID prompt → stay on the lock screen. Tap Unlock → re-prompt.

- [ ] **Step 5: Test background-relock**

  - With lock enabled and library showing, send the app to background (swipe up halfway). Don't return.
  - Wait >30 seconds.
  - Foreground the app → lock screen appears. Authenticate to return to library.
  - Send app to background, return after <5 seconds → no re-lock (you stay on the library).

- [ ] **Step 6: Test privacy blur (app-switcher snapshot)**

  - With lock OFF and library populated, open the app switcher (swipe up from bottom, hold). The app's tile should show the blurred placeholder with the document-icon, NOT the document list.
  - Same test with lock ON, library currently locked: tile shows the blurred placeholder.

- [ ] **Step 7: Sanity — no regressions**

  - Tap a document → viewer opens correctly with its bottom toolbar.
  - Try a fresh scan → works as before.
  - Edit mode + per-page editor still work.

- [ ] **Step 8: Commit milestone**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git commit --allow-empty -m "Milestone: Plan 3 verified end-to-end on device"
  ```

---

## After Plan 3

What lands:

- Settings screen reachable from a gear icon, with App Lock toggle + About row.
- Optional Face ID app lock with 30-second background re-lock threshold.
- App-switcher snapshot blur, always-on.

What remains in the original spec:

- **Plan 4** — Error edge cases: iCloud unavailable / signed out, NSFileVersion conflicts, corrupt PDFs, storage full.
- **Plan 5** — XCUITest golden-path tests with a mocked scanner.

## Self-review notes

- Spec coverage: App Lock toggle ✓, Face ID auth on enable/disable ✓, cold-launch lock ✓, 30s background re-lock ✓, app-switcher blur ✓, About row ✓.
- Placeholder scan: none.
- Type consistency: `AppLockSettings` API matches between class, tests, `LockGate`, `SettingsView`, and `LibraryView` consumer. The `@Bindable` use in LockGate and SettingsView only reads/calls methods; no direct binding.
- Hardware-dependent paths: `LAContext.evaluatePolicy` not unit-tested. State-machine logic (timestamp, transitions) is fully unit-tested.
- Risk: Face ID's behavior in the simulator. The simulator can simulate Face ID via Features → Face ID → Matching Face / Non-matching Face. Smoke test prefers real device.
