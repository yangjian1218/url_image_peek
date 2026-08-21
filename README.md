# ImagePeek

根据图片 URL 或本地图片地址，在表格附近浮窗预览图片。

ImagePeek is a native macOS menu-bar application for instant image preview from spreadsheet cells. The validated product and safety baseline lives in [`PROJECT_HANDOFF.md`](PROJECT_HANDOFF.md).

## Current milestone

This repository currently contains the first Phase 1 skeleton:

- macOS 13+ AppKit menu-bar application (`LSUIElement` agent, no Dock icon)
- SwiftUI settings window
- explicit Accessibility permission status and request boundary
- `SpreadsheetAdapter` contracts and pure active-application classification
- safe no-op WPS and Microsoft Excel adapters
- ImageEngine and PreviewEngine module boundaries
- XCTest coverage for application classification, adapter safety defaults, and permission-request behavior

The adapters do not yet read cells. Image loading, caching, preview panels, shortcuts, clipboard fallback, login-at-launch, and web spreadsheets are intentionally not active in this round.

## Build and test

Open `ImagePeek.xcodeproj` with Xcode 16.1 or run:

```bash
xcodebuild -project ImagePeek.xcodeproj \
  -scheme ImagePeek \
  -configuration Debug \
  -derivedDataPath /tmp/ImagePeekDerivedData \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project ImagePeek.xcodeproj \
  -scheme ImagePeek \
  -configuration Debug \
  -derivedDataPath /tmp/ImagePeekDerivedData \
  CODE_SIGNING_ALLOWED=NO test
```

## Safety baseline

ImagePeek prioritizes system stability over missed previews. The current source contains no global mouse event taps, input swallowing, clipboard access, network requests, OCR, or spreadsheet mutation. Accessibility permission is requested only when the user presses the button in Settings.
