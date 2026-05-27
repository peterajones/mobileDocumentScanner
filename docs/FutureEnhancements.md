# Future Enhancements

A running list of ideas for future versions of Pocket Scanner, organized by intended release. Items here are *candidates*, not commitments — we may drop, defer, or reshape any of them.

Versions earlier than the current shipping release are deleted from this doc as they ship; the history is in git.

---

## Enhancements v1.1

The next release. Six items, scoped to roughly 1-2 weekends of work.

### 1. Launch screen

Replace Xcode's default blank-white launch screen with a tinted background + centered app icon. Current behaviour: brief blank white while iOS is doing app-startup overhead. Better: something that looks like "the app starting" rather than "the app crashed."

- Target file: `LaunchScreen.storyboard` (create if absent) or `UILaunchScreen` dictionary in Info.plist
- ~10 minutes of work

### 2. Smarter default scan name

Currently every new scan defaults to `Scan YYYY-MM-DD HH:mm`. Use the OCR text from the first page to suggest something better — e.g., a receipt becomes `Costco Receipt — May 27`, a recipe becomes `Recipe — Banana Bread`. User can still edit before saving.

- Heuristic in `NameDocumentSheet`: look at the first non-empty OCRObservation strings, run a small set of pattern matchers (`receipt`, `invoice`, `recipe`, leading title-case phrases)
- Falls back to current `Scan YYYY-MM-DD HH:mm` if nothing matches
- ~2 hours

### 3. Multi-select + bulk delete in edit mode

Currently the edit-mode thumbnail strip supports one-at-a-time delete via long-press → context menu. Adding multi-select makes bulk operations practical for power users with multi-page documents.

- Long-press a thumbnail enters multi-select mode
- Subsequent taps toggle selection
- Bottom-bar Edit button changes to a Delete action while in multi-select
- Cancel exits multi-select without changes
- ~half a day

### 4. Apply filter to all pages

Per-page editor currently scopes filter changes to that page. A common case is "apply B&W to the whole document." Add a button in the per-page editor's filter section.

- Button below the filter picker: "Apply to all pages"
- Confirmation dialog (destructive: re-renders + re-OCRs every page)
- Streams through `DocumentMutations.replacePage` per page with the same filter
- Progress indicator since OCR per page takes 1-3 seconds
- ~half a day

### 5. In-app feedback link

A "Send Feedback" row in Settings → opens a `mailto:` URL pre-addressed to the support email with the app version + iOS version pre-filled in the subject.

- New row in `SettingsView` below the About row
- `UIApplication.shared.open(URL(string: "mailto:peterjones@mac.com?subject=Pocket%20Scanner%201.0%20feedback"))`
- 15 minutes

### 6. Folders

Once a user accumulates 50+ scans, the flat list breaks down. Folders are the spec's deferred organizational layer.

- `Folder` value type with a name, optional parent folder reference, and creation date
- Folders are themselves directories inside the iCloud Documents container — leverage filesystem hierarchy directly rather than building an index
- `LibraryView` becomes folder-aware: tap a folder pushes a child view showing its contents; long-press on a doc moves it to a different folder
- Settings → "Show folders" toggle (default ON post-1.1; legacy users keep a flat view until they opt in)
- Significant work: ~2-3 days. Touches `LibraryView`, `MetadataQueryLibraryStore` (folder enumeration), `DocumentStorage` (move operation), and the bottom-toolbar UX (move-to-folder action in the viewer)

---

## Enhancements v1.2 and beyond

Lower priority. Some of these may never ship. The list exists to capture what we considered.

### Polish

- **Sample document on first launch** — pre-populate the library with a "Welcome.pdf" so the empty state has something to demonstrate features against. Removed on first user delete.
- **App Icon variants** — let users pick from a few styles (light, dark, minimal) via iOS 14.3+'s alternate icons API. Power-user feature.

### Filters

- **Stronger B&W preset** — current `CIPhotoEffectNoir` was flagged as subtle. Swap to a tuned `CIColorMonochrome` + contrast bump for more pop on plain documents.
- **Filter at scan time** — pick a filter in the Name & Save sheet before the initial save, applied to every page of that scan. Faster than entering per-page editor for each.

### Search

- **Horizontal highlight accuracy** — currently highlights are vertically accurate but horizontally approximate (system font width ≠ original glyph width). Fix: scale the invisible text horizontally to match each `VNRecognizedTextObservation`'s `boundingBox` width.
- **Cross-document match navigation** — search results currently break context when you tap into a document. Could surface "Match 1 of 7 across 3 documents" with cross-doc prev/next.

### Editing

- **Rotate-in-strip** — a context-menu rotate option on edit-mode thumbnails, avoiding a trip through the per-page editor.
- **Page extraction** — multi-select + "Save as new document" to break apart a scan.

### Library

- **Sort options** — by date, by name, by page count. Currently always newest-first.
- **Grid view** — alternate to list view, larger thumbnails. Useful for visually-driven workflows.

### Platform reach

- **Widget** — recent scans on the home screen. Small (single doc) and medium (4-doc grid) variants.
- **Shortcuts integration** — App Intent for "Scan a document with Pocket Scanner" via Siri / Shortcuts app.
- **iPad layout** — bring back iPad support with a split-view layout (sidebar list + viewer pane) that uses the larger screen properly. Different from "iPhone app on iPad" stretched mode.

### Error handling (verification)

These code paths exist but were never exercised on a real device. v1.2 should provoke each and confirm the UX works:

- **Storage-full save failure** — fill the device, attempt a scan, verify the AlertCenter retry path works.
- **NSFileVersion conflict** — edit the same doc on two devices simultaneously, verify the picker UI works.
- **Corrupt PDF "Try to recover"** path — currently the library shows a 🚫 row with a Delete action; spec also called for a "Try to recover" action using PDFKit's lenient reader.

### Business / pricing

- **Launch sale** — drop to $2.99 for the first week post-launch, then return to $4.99. App Store users see "was $4.99, now $2.99" as a deal.
- **Tip jar IAP** — one-time "Buy the developer a coffee" tiers ($1.99 / $4.99 / $9.99) in Settings. Some users like to support indie devs they like.

### Internationalization

- **Localizable strings** — currently all UI is English. Likely targets: French, Spanish, German.
- **OCR language detection** — Vision supports many languages but defaults to device locale. Surface a language picker in Settings for users who scan multilingual documents.
