# ImagePeek Global Selection Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in, clipboard-free image preview for a selected URL in any app that exposes its selection through macOS Accessibility.

**Architecture:** A focused Accessibility reader obtains only selected text from the frontmost app, except WPS and Excel where an existing cell-preview path already owns the interaction. A coordinator converts observed mouse/key events into a one-second delayed request and cancels it when the selection or pointer changes. A dedicated preview panel keeps existing spreadsheet previews independent.

**Tech Stack:** Swift 5, AppKit, ApplicationServices, SwiftUI, XCTest.

**Spec:** Confirmed user design in this task: default-off setting; wait one second after selecting a complete image URL; hide on pointer movement, selection cancellation, or app change; no clipboard, simulated keystrokes, browser injection, or input interception; silently skip apps without Accessibility-selected-text support.

## Global Constraints

- Retain macOS 13.0 and arm64 + x86_64 support.
- Global input is observation-only: never consume, modify, synthesize, or delay events.
- Read selected text only through Accessibility; never persist it or fall back to the clipboard.
- Existing WPS, Excel, and Feishu behavior remains unchanged.
- The setting defaults to disabled, including after decoding older settings.

---

### Task 1: Selection policy and reader

**Files:**
- Create: `ImagePeek/AppShell/GlobalSelectionPreview.swift`
- Modify: `ImagePeekTests/SpreadsheetCoreTests.swift`

**Interfaces:** Produces `GlobalSelectionPreviewPolicy`, `GlobalSelectedTextReading`, and `SystemGlobalSelectedTextReader`.

- [x] **Step 1: Write the failing test**

```swift
func testGlobalSelectionPolicyAcceptsOneImageURL() {
    XCTAssertTrue(GlobalSelectionPreviewPolicy.isEligible(selectedText: " https://example.com/image.png "))
    XCTAssertFalse(GlobalSelectionPreviewPolicy.isEligible(selectedText: "look https://example.com/image.png"))
}
```

- [x] **Step 2: Run the test and verify it fails**

Run: `xcodebuild test -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' -only-testing:ImagePeekTests/SpreadsheetCoreTests`

Expected: `GlobalSelectionPreviewPolicy` does not exist.

- [x] **Step 3: Implement the minimal policy and reader**

```swift
enum GlobalSelectionPreviewPolicy {
    static func isEligible(selectedText: String) -> Bool {
        ImageSourceResolver().resolve(selectedText) != nil
    }
}
```

The reader gets `kAXFocusedUIElementAttribute` from the frontmost process and only reads `kAXSelectedTextAttribute`, returning `nil` for untrusted Accessibility, missing attributes, or non-string values.

- [x] **Step 4: Run the test and verify it passes**

Run: `xcodebuild test -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' -only-testing:ImagePeekTests/SpreadsheetCoreTests`

- [x] **Step 5: Commit**

```bash
git add ImagePeek/AppShell/GlobalSelectionPreview.swift ImagePeekTests/SpreadsheetCoreTests.swift
git commit -m "feat: add global selection preview policy"
```

### Task 2: Delay coordinator and stored setting

**Files:**
- Modify: `ImagePeek/AppShell/GlobalSelectionPreview.swift`
- Modify: `ImagePeek/AppShell/AppSettings.swift`
- Modify: `ImagePeekTests/PreviewEngineTests.swift`
- Modify: `ImagePeekTests/SpreadsheetCoreTests.swift`

**Interfaces:** Produces `GlobalSelectionPreviewCoordinator` and `globalSelectionPreviewEnabled: Bool`.

- [x] **Step 1: Write the failing tests**

```swift
func testGlobalSelectionCoordinatorUsesOneSecondDelay() {
    XCTAssertEqual(GlobalSelectionPreviewCoordinator.delay, 1)
}

func testSettingsDecodeDefaultsGlobalSelectionPreviewToDisabled() throws {
    let settings = try JSONDecoder().decode(ImagePeekSettings.self, from: Data("{}".utf8))
    XCTAssertFalse(settings.globalSelectionPreviewEnabled)
}
```

- [x] **Step 2: Run tests and verify they fail**

Run: `xcodebuild test -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' -only-testing:ImagePeekTests/PreviewEngineTests -only-testing:ImagePeekTests/SpreadsheetCoreTests`

- [x] **Step 3: Implement the minimum**

```swift
struct GlobalSelectionPreviewCoordinator {
    static let delay: TimeInterval = 1
}
```

Use a runtime generation counter to invalidate delayed callbacks. The pure coordinator must not own timers, tasks, or AppKit objects.

- [x] **Step 4: Run tests and verify they pass**

Run: `xcodebuild test -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' -only-testing:ImagePeekTests/PreviewEngineTests -only-testing:ImagePeekTests/SpreadsheetCoreTests`

- [x] **Step 5: Commit**

```bash
git add ImagePeek/AppShell/GlobalSelectionPreview.swift ImagePeek/AppShell/AppSettings.swift ImagePeekTests/PreviewEngineTests.swift ImagePeekTests/SpreadsheetCoreTests.swift
git commit -m "feat: add global selection preview setting"
```

### Task 3: Runtime integration and settings UI

**Files:**
- Modify: `ImagePeek/AppShell/ImagePeekApp.swift`
- Modify: `ImagePeek/AppShell/SettingsView.swift`
- Modify: `ImagePeekTests/SpreadsheetCoreTests.swift`

**Interfaces:** Consumes the Task 1 reader/policy and Task 2 setting/delay. Uses a separate `PreviewPanelController` for global selection previews.

- [x] **Step 1: Write the failing event-policy test**

```swift
func testGlobalSelectionEventPolicySchedulesOnMouseUpAndCancelsOnPointerMove() {
    XCTAssertTrue(GlobalSelectionPreviewEventPolicy.shouldSchedule(for: .mouseReleased))
    XCTAssertTrue(GlobalSelectionPreviewEventPolicy.shouldCancel(for: .pointerMoved))
}
```

- [x] **Step 2: Run the test and verify it fails**

Run: `xcodebuild test -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' -only-testing:ImagePeekTests/SpreadsheetCoreTests`

- [x] **Step 3: Implement observation-only runtime integration**

Register `NSEvent.addGlobalMonitor` for `.leftMouseUp`, `.leftMouseDown`, `.mouseMoved`, `.leftMouseDragged`, and `.keyUp`. The handler only schedules or cancels work. The delayed read requires enabled setting, the same frontmost app, an app other than WPS or Excel, and a resolvable image URL. It loads through the existing image loader and displays near the release point.

Hide only the dedicated global panel on pointer movement, click, key-based selection change, app switch, disabled setting, or invalid selection. Add the `Preview selected image URL anywhere` toggle and copy explaining that it is Accessibility-only and never uses the clipboard.

- [x] **Step 4: Run full verification**

Run: `xcodebuild test -project ImagePeek.xcodeproj -scheme ImagePeek -destination 'platform=macOS' && xcodebuild build -project ImagePeek.xcodeproj -scheme ImagePeek -configuration Debug -destination 'platform=macOS'`

Manual: enable toggle; select a direct image URL in TextEdit or browser; wait one second; confirm independent preview appears; move pointer and confirm it disappears; confirm WPS/Excel/Feishu previews and shortcuts remain normal; disable toggle and confirm no global preview.

- [ ] **Step 5: Commit and push**

```bash
git add ImagePeek/AppShell ImagePeekTests docs/superpowers/plans/2026-08-25-imagepeek-global-selection-preview.md
git commit -m "feat: preview selected image URLs globally"
git push origin feature/wps-accessibility-adapter
```

## Self-review

- Spec coverage: the tasks cover the opt-in setting, one-second delay, Accessibility-only text access, automatic hiding, separate panels, and regression tests.
- Type consistency: Task 1 creates the reader/policy, Task 2 creates delay/settings, and Task 3 consumes both.
