# ImagePeek Phase 1 Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a compilable macOS 13+ ImagePeek menu-bar application skeleton that exposes the approved AppShell, permission, spreadsheet adapter, image, and preview boundaries without implementing cross-application input interception.

**Architecture:** AppKit owns the application lifecycle, status item, and settings window, while SwiftUI renders settings content. Spreadsheet-specific behavior is isolated behind `SpreadsheetAdapter`; the first round provides safe WPS and Excel no-op adapters plus a pure active-application classifier that can be unit tested without observing the system.

**Tech Stack:** Swift, AppKit, SwiftUI, ApplicationServices Accessibility API, XCTest, Xcode 16.1

**Spec:** `PROJECT_HANDOFF.md`

## Global Constraints

- Minimum deployment target is macOS 13 Ventura.
- The application is a menu-bar resident agent and must set `LSUIElement` to `true`.
- AppKit is the primary UI framework; SwiftUI is limited to the settings view in this round.
- Accessibility is the only requested system permission; screen recording is not requested.
- No global mouse event taps, mouse event swallowing, simulated dragging, bare-letter global shortcuts, clipboard fallback, network request, or browser preview is implemented in this round.
- WPS- and Excel-specific behavior remains inside their adapters; Phase 2 web sheets are out of scope.
- A failed adapter returns `nil`; it must not retry, mutate spreadsheet content, or trigger clipboard activity.
- The directory is not currently a Git repository, so implementation does not initialize Git or create commits without user authorization.

---

### Task 1: Core spreadsheet contracts and application classification

**Files:**
- Create: `ImagePeekTests/SpreadsheetCoreTests.swift`
- Create: `ImagePeek/SpreadsheetEngine/SpreadsheetModels.swift`
- Create: `ImagePeek/SpreadsheetEngine/SpreadsheetAdapter.swift`
- Create: `ImagePeek/SpreadsheetEngine/ActiveAppDetector.swift`

**Interfaces:**
- Produces: `SpreadsheetApp`, `CellContext`, `AdapterCapability`, `SpreadsheetAdapter`, and `ActiveAppDetector.classify(bundleIdentifier:)`.

- [x] Write tests proving known WPS and Excel bundle identifiers classify correctly, unknown/nil bundle identifiers are rejected, and no-op adapters declare safe capabilities and return no cell.
- [x] Run the focused test target and confirm RED because the production contracts do not exist.
- [x] Add the smallest production types and pure classifier needed to satisfy the tests.
- [x] Re-run the focused tests and confirm GREEN.

### Task 2: Safe adapter placeholders and engine boundaries

**Files:**
- Create: `ImagePeek/SpreadsheetEngine/WPSAdapter.swift`
- Create: `ImagePeek/SpreadsheetEngine/ExcelAdapter.swift`
- Create: `ImagePeek/ImageEngine/ImageEngine.swift`
- Create: `ImagePeek/PreviewEngine/PreviewEngine.swift`
- Modify: `ImagePeekTests/SpreadsheetCoreTests.swift`

**Interfaces:**
- Produces: `WPSAdapter`, `ExcelAdapter`, `ImageEngine`, and `PreviewEngine`.
- Consumes: `SpreadsheetAdapter`, `SpreadsheetApp`, and `AdapterCapability` from Task 1.

- [x] Add focused tests for the adapters' app identity, disabled direct-read capabilities, disabled clipboard fallback, and `nil` cell result.
- [x] Run tests and confirm RED because the adapter types do not exist.
- [x] Implement no-op adapters and empty engine namespace types only.
- [x] Re-run tests and confirm GREEN.

### Task 3: Accessibility permission boundary

**Files:**
- Create: `ImagePeek/AppShell/PermissionManager.swift`
- Create: `ImagePeekTests/PermissionManagerTests.swift`

**Interfaces:**
- Produces: `AccessibilityChecking`, `SystemAccessibilityChecker`, and `PermissionManager` with read-only `isAccessibilityGranted` plus explicit `requestAccessibility()`.

- [x] Write tests using an injected checker to prove status reads are side-effect free and explicit requests are delegated once.
- [x] Run tests and confirm RED because `PermissionManager` does not exist.
- [x] Implement dependency-injected permission checking; keep the actual prompt behind the explicit request method.
- [x] Re-run tests and confirm GREEN.

### Task 4: Menu-bar application and SwiftUI settings

**Files:**
- Create: `ImagePeek/AppShell/ImagePeekApp.swift`
- Create: `ImagePeek/AppShell/MenuBarController.swift`
- Create: `ImagePeek/AppShell/SettingsWindowController.swift`
- Create: `ImagePeek/AppShell/SettingsView.swift`
- Create: `ImagePeek/Resources/Assets.xcassets/Contents.json`
- Create: `ImagePeek/Info.plist`
- Create: `ImagePeek/ImagePeek.entitlements`

**Interfaces:**
- Consumes: `PermissionManager` from Task 3.
- Produces: a status item with Settings and Quit actions and a non-activating background app lifecycle.

- [x] Implement the minimal AppKit lifecycle and status item wiring with a SwiftUI settings surface.
- [x] Ensure opening Settings activates ImagePeek only for the settings window; closing it returns control normally.
- [x] Keep the UI free of input event monitors, clipboard access, network access, and spreadsheet mutations.

### Task 5: Xcode project and verification

**Files:**
- Create: `ImagePeek.xcodeproj/project.pbxproj`
- Create: `ImagePeek.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- Create: `README.md`

**Interfaces:**
- Produces: `ImagePeek` app and `ImagePeekTests` test targets targeting macOS 13+.

- [x] Wire all production and test files into the Xcode project with automatic Info.plist generation disabled in favor of the reviewed plist.
- [x] Run `xcodebuild -project ImagePeek.xcodeproj -scheme ImagePeek -configuration Debug -derivedDataPath /tmp/ImagePeekDerivedData CODE_SIGNING_ALLOWED=NO build` and require exit code 0.
- [x] Run `xcodebuild -project ImagePeek.xcodeproj -scheme ImagePeek -configuration Debug -derivedDataPath /tmp/ImagePeekDerivedData CODE_SIGNING_ALLOWED=NO test` and require zero test failures.
- [x] Inspect the resulting source for forbidden event-tap, clipboard, OCR, network, and Phase 2 implementation patterns.
- [x] Update README with scope, build instructions, and explicit first-round non-goals.
