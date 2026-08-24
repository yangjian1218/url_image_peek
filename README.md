# ImagePeek

根据图片 URL 或本地图片地址，在表格附近浮窗预览图片。

ImagePeek is a native macOS menu-bar application for instant image preview from spreadsheet cells. The validated product and safety baseline lives in [`PROJECT_HANDOFF.md`](PROJECT_HANDOFF.md).

## Current milestone

This repository contains the Phase 1 native spreadsheet MVP:

- macOS 13+ AppKit menu-bar application (`LSUIElement` agent, no Dock icon)
- SwiftUI settings window
- explicit Accessibility permission status and request boundary
- `SpreadsheetAdapter` contracts and pure active-application classification
- WPS clipboard fallback and Excel AppleScript fallback, both constrained to the frontmost spreadsheet
- remote/local image loading, OSS optimization, memory and disk caches
- non-activating preview panel, pixel dimensions, conditional shortcuts, and pinned preview
- persisted settings, image-column filtering, and login-item registration
- XCTest coverage for application classification, adapter safety defaults, cache behavior, and preview policy

Web spreadsheets remain Phase 2 work.

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

## Release packaging

See [docs/RELEASE.md](docs/RELEASE.md) for the unsigned review archive and the later Developer ID signing/notarization flow. Distribution credentials stay in the local Keychain and are never committed.

## Safety baseline

ImagePeek prioritizes system stability over missed previews. It does not swallow global mouse events, mutate spreadsheet data, use OCR, or show system alerts during preview failures. Accessibility is limited to reading the frontmost supported spreadsheet; WPS clipboard fallback saves and restores the user's clipboard.
