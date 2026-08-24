# ImagePeek Phase 1 Operations Design

## Goal

Complete the operational controls and diagnostics omitted from the native WPS and Microsoft Excel MVP. The work must preserve the established safety boundary: ImagePeek reads only the frontmost supported spreadsheet, does not mutate spreadsheet content, and does not consume unrelated input.

## Scope

The phase adds:

- session-only, privacy-preserving image-load diagnostics;
- disk-cache summary and a user-initiated ImagePeek-only cache clear operation;
- persisted settings for pixel dimensions, load-source visibility, disk-cache byte limit, and disk-cache retention age;
- settings sections for Preview, Cache, and Diagnostics.

The phase does not add browser spreadsheet support, telemetry, URL history, OCR, new global shortcuts, drag behaviour, or changes to WPS/Excel cell-reading strategies.

## Architecture

`RemoteImageLoader` remains the single owner of request cancellation and cache lookup. It will expose a small load outcome suitable for diagnostics, without retaining raw URL or image data in the diagnostic model.

A `RuntimeDiagnostics` value records only aggregate session counts and the most recent result:

- elapsed loading time;
- result kind: success, failure, or cancellation;
- image source for successful remote loads: network, disk cache, or memory cache.

`PreviewRuntimeController` updates this value after each image request and makes a snapshot available to the settings UI. Local-image loads remain valid preview operations but have no remote cache source.

`DiskImageCache` gains summary and clear operations. Both are confined to its configured cache directory. Clear is explicit and user-initiated; failures safely report an unavailable summary rather than interrupt the user.

Cache policy is loaded from `ImagePeekSettings` when the runtime starts. The defaults are one GiB and thirty days, matching the existing cache behavior. Bounds validation prevents zero, negative, or unreasonably large user-entered values from reaching the cache implementation.

## Settings and UI

The existing General, Accessibility, and Spreadsheet sections remain unchanged. Three new sections are added:

- **Preview**: toggles for pixel dimensions and remote load source.
- **Cache**: maximum size in GiB, retention in days, current entry/byte summary, and a Clear Cache button.
- **Diagnostics**: session counts and the most recent load summary.

The default behavior is compatible with the current application: pixel dimensions are shown, load source is hidden, disk cache is one GiB, and retention is thirty days. The settings window remains non-intrusive; errors appear as inline text rather than system alerts.

The preview caption can include the configured pixel dimensions and source. If both are disabled, no caption overlay is shown.

## Data Flow

1. The runtime reads persisted settings on startup and configures image loading and preview presentation.
2. A selected WPS or Excel cell resolves to a preview request using the existing adapter path.
3. The loader returns a success, failure, or cancellation result; its source is retained only for the active caption and aggregate diagnostic snapshot.
4. The runtime updates the panel and diagnostics snapshot on the main actor.
5. The settings view requests cache and diagnostics snapshots without reading spreadsheet content or activating a spreadsheet application.

## Error Handling and Safety

- Cache directory read/write failures result in cache misses or an unavailable summary; previews can still use memory or network data.
- Clearing cache affects only ImagePeek's cache directory and is idempotent.
- A cancelled obsolete request does not increment failure counts and cannot replace a newer preview.
- No URL, local path, spreadsheet cell value, clipboard text, or image bytes are persisted in diagnostics.
- Existing conditional shortcut policy and Accessibility boundaries are unchanged.

## Test Plan

- Write red tests for settings defaults, Codable backward compatibility, and input bounds.
- Test diagnostic aggregation for memory, disk, network, local, failed, and cancelled outcomes.
- Test cache summary and explicit clear operations in a temporary ImagePeek cache directory.
- Test caption composition for each visibility configuration.
- Run the full XCTest suite, a Release build with signing disabled, and source safety checks before committing.

## Completion Criteria

- The new settings persist across restart and default safely when old settings data lacks new fields.
- The diagnostics UI exposes only aggregate session information.
- Cache clearing is scoped to ImagePeek data and does not block previews.
- All automated tests pass and no WPS/Excel input or permission behavior changes.
