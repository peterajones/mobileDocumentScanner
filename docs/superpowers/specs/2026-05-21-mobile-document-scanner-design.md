# Mobile Document Scanner — Design Spec

**Date:** 2026-05-21
**Platform:** iOS 17+, native SwiftUI
**Status:** Draft, pending user review

## Goal

A single-user iOS app for scanning paper documents to PDF and keeping a searchable, on-device library. Scans sync across the user's devices via iCloud Drive and are visible to the system Files app.

## Non-goals (v1)

- Multi-user accounts, sharing, or any backend service
- Android or cross-platform
- Folders, tags, or hierarchical organization (flat list only)
- Form/field extraction or business-card structuring
- Cloud OCR / third-party services (all processing on-device)

## Decisions summary

| Decision | Choice |
| --- | --- |
| Platform | iOS 17+, SwiftUI |
| Capture | Apple `VNDocumentCameraViewController` (VisionKit) |
| OCR | Apple `Vision` framework, on-device, post-capture |
| Storage | iCloud Drive (app's ubiquity container), visible to Files.app |
| Library model | Flat list, newest first, search by name + OCR text |
| Naming | Modal name prompt on save with date default |
| Editing | Reorder, delete, append, re-crop / rotate pages |
| Privacy lock | Optional Face ID / passcode (off by default) |

## Architecture

### App shape

A single SwiftUI `App` target. Root scene = library, gated by an optional `LockGate` when Face ID lock is enabled. Capture and naming are sheets; viewer and settings are pushes on a single `NavigationStack`. No tabs, no multi-window.

### Modules

```
App/         @main, root scene, LockGate
Library/     LibraryView, LibraryStore (NSMetadataQuery wrapper), DocumentSummary
Capture/     VisionKit wrapper, NameDocumentSheet
Pipeline/    ScanPipeline actor: pages → OCR → PDF assembly
Viewer/      DocumentViewerView (PDFKit), page-edit mode
Settings/    SettingsView, AppLock toggle
Storage/     iCloud URL helpers, NSFileCoordinator wrappers, conflict resolution
```

Each module has one purpose and depends on a narrow surface from its neighbors. `Pipeline` is the only module that touches both `Vision` and `PDFKit`; `Library` never imports `Vision`; `Capture` never imports iCloud APIs.

### Frameworks

- `SwiftUI` — UI
- `VisionKit` — `VNDocumentCameraViewController` for capture
- `Vision` — `VNRecognizeTextRequest` (OCR), `VNDetectDocumentSegmentationRequest` (re-crop suggestions)
- `PDFKit` — assemble PDFs, embed invisible text layer, render in viewer, edit pages
- `LocalAuthentication` — Face ID / passcode for optional app lock
- Foundation: `NSMetadataQuery`, `NSFileCoordinator`, `NSFilePresenter`, `NSFileVersion`

### Storage model

Each scan is a single self-contained PDF file in the app's iCloud Documents container:

```
<iCloud ubiquity container>/Documents/
  Lease Agreement.pdf
  Costco Receipt.pdf
  Tax Return 2025.pdf
```

No sidecar files. OCR text is embedded in the PDF itself as invisible text annotations (a "searchable PDF"), so:

- The exported PDF is searchable in any reader (Preview, Acrobat, other iOS apps).
- Our own library search reads the embedded text — there is no separate index that can drift.
- AirDropping a PDF out of the app preserves searchability.

PDF metadata (`PDFDocument.documentAttributes`) stores `createdAt` and `appVersion`. Display name = filename (no extension).

When iCloud is unavailable, files are written to the app's local `Documents/` directory and tagged with a `.pending-sync` extended attribute (`xattr`). The library lists local and iCloud files in a single sorted view; on iCloud re-availability the storage layer migrates pending-sync files into the iCloud container. This is the only divergence from the iCloud-Documents-only model and is treated as a transient state.

### Entitlements & Info.plist

- `iCloud Documents` entitlement, ubiquity container identifier
- `NSUbiquitousContainerIsDocumentScopePublic` = `YES`, `NSUbiquitousContainerSupportedFolderLevels` = `Any` so Files.app sees the folder
- `NSCameraUsageDescription` (VisionKit needs it)
- `NSFaceIDUsageDescription` (LocalAuthentication)

## Screens & navigation

### Library (root)

- Large title "Documents", iOS-standard nav bar
- Top-left: text button "Settings"
- Top-right: "+" button → presents Capture sheet
- Search field beneath nav bar, filters by document name + embedded OCR text
- `List` of rows, newest first. Each row: 44×56 first-page thumbnail · document name (semibold) · "MMM d · N page(s)" · chevron
- Pull-to-refresh forces an `NSMetadataQuery` re-scan
- Empty state: centered "No documents yet — tap + to scan"
- Locally-pending (not yet synced) items show a small "↻" badge

### Capture sheet (modal)

Wraps `VNDocumentCameraViewController` full-screen. On `didFinishWith scan:`:

- Do not dismiss immediately; transition to **Name & Save sheet** in the same modal context.
- Kick off `ScanPipeline.process(scan)` as a `Task` so OCR + PDF assembly happens while the user is naming.

### Name & Save sheet (modal continuation)

- `TextField` defaulting to `"Scan YYYY-MM-DD HH:mm"` (locale-formatted)
- "Save" (primary) and "Cancel" buttons
- Save: awaits the pipeline `Task` if not yet done (shows inline spinner with "Processing page 3 of 5…"), then writes to iCloud and dismisses.
- Cancel: cancels the pipeline `Task` and dismisses without writing.

### Viewer (push)

- `PDFView`, single-page paging, pinch-zoom, two-finger rotation gesture suppressed
- Nav bar: title = filename (tap to rename inline), trailing "Edit" + share + delete
- Delete prompts confirm
- Detects `NSFileVersion` conflicts on open and presents a "Keep this device's / Keep other version" picker

### Edit mode (within viewer)

- Bottom strip: scrollable row of page thumbnails
- Drag to reorder
- Tap a thumbnail to enter per-page editor (re-crop + rotate, with `VNDetectDocumentSegmentationRequest` initializing the quad)
- "Add pages" button → re-opens VisionKit, appends new pages through the same pipeline (OCR runs for the new pages only)
- Trash button on selected thumbnail; deleting the last page prompts "Delete entire document?"
- "Done" exits edit mode and commits via coordinated write

### Settings (push)

- Row: "App Lock" toggle. Enabling prompts Face ID first (and on disable too).
- Row: "About / Version"
- Designed to grow (export options, default naming pattern, etc.)

## Data flow — capture to saved PDF

```text
[+] tap
  → VNDocumentCameraViewController (modal)
  → user scans N pages → VNDocumentCameraScan
  → ScanPipeline.process(scan)  [actor, Task]
       For each page image:
         VNRecognizeTextRequest → [VNRecognizedTextObservation]
       Build PDFDocument:
         For each (image, observations):
           PDFPage(image:)
           Overlay invisible text annotations at observation bounding boxes
         Set documentAttributes: createdAt, appVersion
       Returns: (PDFDocument, concatenatedOCRText)

  In parallel:
    → Name & Save sheet
    → user types name, taps Save
    → await pipeline Task
    → Storage.write(pdfDocument, filename) via NSFileCoordinator
       - Resolve filename collisions: "Name.pdf" → "Name (2).pdf"
       - Coordinated write to <iCloud Documents>/<filename>.pdf
       - If iCloud unavailable, write to local Documents/ with `.pending-sync` xattr

  → NSMetadataQuery picks up new file → LibraryStore refreshes → row appears
```

`ScanPipeline` is implemented as a Swift `actor`. Capture and naming UI are SwiftUI views with no direct dependency on the pipeline beyond a `Task` handle they can await or cancel.

## Search & library indexing

- `LibraryStore` is an `@Observable` class running an `NSMetadataQuery` scoped to `NSMetadataQueryUbiquitousDocumentsScope`, filtered to `.pdf` extension.
- For each result it builds a `DocumentSummary { url, displayName, createdAt, pageCount, ocrSnippet, thumbnail }` by opening the PDF, reading metadata, extracting embedded text via `PDFDocument.string`, rendering the first page to a thumbnail (`PDFPage.thumbnail(of:for:)`).
- Summaries are cached in memory; we re-build only for changed/new URLs from query updates.
- Search: case-insensitive substring match against `displayName` and `ocrSnippet`.
- For v1 we do not highlight matched text in the row. Future enhancement.
- If the in-memory summary cache grows large (hundreds of docs with multi-MB text), we can swap to a lightweight on-device index (SQLite FTS, or `SearchKit`) without changing the storage model. Not built in v1.

## Privacy lock

- `@AppStorage("appLockEnabled")` boolean toggled in Settings.
- Root view wraps the library in a `LockGate`:
  - On cold launch with lock enabled: present an opaque lock screen, immediately call `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`. Success → unlock. Failure / cancel → stay locked with a "Try again" button.
  - On scene transition to background (`UIScene.willDeactivateNotification`): record timestamp.
  - On return to active: if `>30s` since deactivation and lock enabled, re-lock.
  - While locked, render a blurred placeholder (`UIVisualEffectView` style `.systemThickMaterial`) so no document names or thumbnails leak to the iOS app switcher.
- Independent of the LockGate, present a blur overlay on `willResignActiveNotification` to cover the app switcher snapshot regardless of lock state — sensitive content shouldn't appear there even with lock off.
- Enabling and disabling the lock both require successful authentication first.

## Error handling

User-facing errors flow through a small `AppAlert` system rendered as `.alert` modifiers on the root view; internal errors log via `OSLog` with categorized subsystems (`Pipeline`, `Storage`, `Library`).

| Case | Behavior |
| --- | --- |
| iCloud Drive disabled for app | First-launch onboarding screen explains, with "Try anyway (local only)" escape; local-only docs get a "↻ pending sync" badge and migrate to iCloud automatically when it becomes available. |
| Storage full on save | Alert "Couldn't save — storage full" with Retry; PDF held in memory until sheet dismissed. |
| Camera permission denied | Capture sheet replaced with "Camera access needed → Open Settings" view. |
| Vision OCR fails on a page | Save PDF without a text layer for that page; log; no user-visible error. |
| iCloud file conflict (`NSFileVersion`) | Viewer detects on open, presents "Keep this version / Keep other version" picker. |
| Corrupt PDF | Library row shows 🚫 thumbnail; tap offers "Delete" or "Try to recover". |
| App backgrounded mid-pipeline | Pipeline `Task` runs detached from view lifecycle; completes if iOS lets us; otherwise discarded silently. User can re-scan. |

## Testing strategy

**Unit tests (XCTest):**

- `ScanPipeline` with fixture page images — asserts PDF page count, that OCR text appears in `PDFDocument.string`, that a single-page Vision failure produces a valid PDF with that page missing its text layer.
- `Storage` filename collision resolution and conflict resolution policy.
- `LibraryStore` summary building from fixture PDFs (name, page count, OCR snippet).

**Snapshot tests:**

- PDFKit thumbnails for known fixture PDFs render consistently across iOS versions.

**UI tests (XCUITest):**

- Golden path: launch → tap + → injected mock scanner returns fixture pages → name → save → row appears in library → open viewer.
- Edit-mode happy path: reorder two pages, delete a page, exit Edit, verify persistence.
- App lock enable → background → relaunch → Face ID prompt (mocked via `LAContext` injection).

Three to five UI tests, not exhaustive. VisionKit is fronted by a `DocumentScannerProtocol` so UI tests inject a fixture-pages stub instead of opening the camera.

**Manual / device-only smoke tests:**

- Real iCloud sync between two devices
- Camera permission flow (first denial, settings recovery)
- Face ID on hardware
- Files.app visibility of the documents folder

## Open questions for implementation

- Exact PDF page size: scale source image to fit Letter at 200 DPI vs preserve source aspect — decide during pipeline implementation based on what looks right.
- Whether to compress page images (JPEG inside PDF) — VisionKit gives high-res images that produce large PDFs; revisit after measuring.
- Thumbnail cache eviction policy if the library grows large — measure first.

These are deliberately deferred. None block the architecture above.
