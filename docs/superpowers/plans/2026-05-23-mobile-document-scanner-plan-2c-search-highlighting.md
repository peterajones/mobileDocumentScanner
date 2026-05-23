# Mobile Document Scanner — Plan 2c: Search highlighting in the viewer

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the user taps a result from the library's search, open the viewer with all matches of the search term highlighted in the PDF and prev/next buttons in the bottom toolbar to step through them.

**Architecture:** `LibraryView` already filters documents by their embedded OCR text. We pass the current `searchText` through the `navigationDestination` to `DocumentViewerView`. The viewer holds a `SearchHighlight` helper that calls `PDFDocument.findString(_:withOptions:)` to get all matches, sets them as `PDFView.highlightedSelections` for yellow background highlighting, and tracks a current match index so prev/next can step through with `PDFView.setCurrentSelection` + `PDFView.go(to:)`. The bottom toolbar gains a counter ("3 of 12") and prev/next buttons when matches exist.

**Tech Stack:** SwiftUI, `PDFKit` (`PDFDocument.findString`, `PDFView.highlightedSelections`, `PDFView.setCurrentSelection`, `PDFView.go(to:)`, `PDFSelection`).

**Spec:** Not in the original design doc — feature request from user. Justification: search across multi-page documents is much more useful when you can see which line matches, not just that the document matches.

**Prerequisite plans:** All prior plans completed and verified on device.

---

## A note for the first-time iOS developer

PDFKit's search machinery is mostly hidden behind a few methods on `PDFDocument` and `PDFView`:

- **`PDFDocument.findString(_ string: String, withOptions: NSString.CompareOptions) -> [PDFSelection]`** — runs a synchronous search across all pages and returns one `PDFSelection` per match.
- **`PDFView.highlightedSelections: [PDFSelection]?`** — when set, every match in the array is rendered with a yellow background. This stays visible as the user scrolls.
- **`PDFView.setCurrentSelection(_ selection: PDFSelection?, animate: Bool)`** — sets *the* selected match (rendered in iOS blue overlay). Different from `highlightedSelections` — both can coexist.
- **`PDFView.go(to: PDFDestination)`** or **`PDFView.go(to: PDFSelection)`** — scroll/navigate to a target.

So our flow is: build all selections via `findString`, set them all as `highlightedSelections` (yellow background everywhere), then `setCurrentSelection` + `go(to:)` for the currently-active match (blue overlay + scrolled into view).

## File structure (target end-state of Plan 2c)

```text
DocumentScanner/
  Viewer/
    SearchHighlight.swift                   # NEW: pure-ish state machine for matches + current index
    DocumentViewerView.swift                # MODIFY: accept searchTerm; drive highlights; bottom-bar prev/next
  Library/
    LibraryView.swift                       # MODIFY: pass searchText to navigationDestination
DocumentScannerTests/
  SearchHighlightTests.swift                # NEW: index math (prev/next wrap, empty, single match)
```

After Plan 2c:

- Type in the library search bar → list filters.
- Tap a matching document → viewer opens; all matches show with yellow highlight; first match is scrolled into view and selected (blue overlay).
- Bottom toolbar shows "3 of 12" and ← / → arrows (only when matches exist).
- Tap → to advance, ← to go back; wraps at the ends.
- Open a doc with no matches (e.g., via the library when search is empty) → no highlight controls in the bottom bar.

---

## Task 1: SearchHighlight helper — pure state machine

**Files:**
- Create: `DocumentScanner/DocumentScanner/Viewer/SearchHighlight.swift`
- Create: `DocumentScanner/DocumentScannerTests/SearchHighlightTests.swift`

A small `@Observable` class holding the list of matches + the current index, with `next()` / `previous()` that wrap. Doesn't touch PDFKit's `findString` directly — that runs once when the viewer constructs the helper.

- [ ] **Step 1: Write the failing tests**

  ```swift
  import XCTest
  import PDFKit
  @testable import DocumentScanner

  @MainActor
  final class SearchHighlightTests: XCTestCase {

      func test_empty_hasNoCurrent() {
          let h = SearchHighlight(matches: [])
          XCTAssertNil(h.currentIndex)
          XCTAssertEqual(h.matchCount, 0)
      }

      func test_initialState_isFirstMatch() {
          let h = SearchHighlight(matches: makeMatches(3))
          XCTAssertEqual(h.currentIndex, 0)
          XCTAssertEqual(h.matchCount, 3)
      }

      func test_next_advancesByOne() {
          let h = SearchHighlight(matches: makeMatches(3))
          h.next()
          XCTAssertEqual(h.currentIndex, 1)
      }

      func test_next_wrapsAtEnd() {
          let h = SearchHighlight(matches: makeMatches(3))
          h.next(); h.next()       // 1 → 2
          h.next()                  // wraps to 0
          XCTAssertEqual(h.currentIndex, 0)
      }

      func test_previous_decrementsByOne() {
          let h = SearchHighlight(matches: makeMatches(3))
          h.next()                  // 1
          h.previous()              // 0
          XCTAssertEqual(h.currentIndex, 0)
      }

      func test_previous_wrapsAtStart() {
          let h = SearchHighlight(matches: makeMatches(3))
          h.previous()              // wraps to 2
          XCTAssertEqual(h.currentIndex, 2)
      }

      func test_nextOnSingleMatch_staysAtZero() {
          let h = SearchHighlight(matches: makeMatches(1))
          h.next()
          XCTAssertEqual(h.currentIndex, 0)
      }

      // MARK: - Helpers

      /// Returns `count` placeholder PDFSelections so the test only exercises
      /// SearchHighlight's index logic — not PDFKit's find behavior.
      private func makeMatches(_ count: Int) -> [PDFSelection] {
          let doc = PDFDocument()
          for _ in 0..<count {
              let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
              let img = renderer.image { _ in
                  UIColor.white.setFill()
                  UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 100))
              }
              doc.insert(PDFPage(image: img)!, at: doc.pageCount)
          }
          return (0..<count).compactMap { idx -> PDFSelection? in
              guard let page = doc.page(at: idx) else { return nil }
              return PDFSelection(document: doc).adding(page: page)
          }
      }
  }

  // PDFSelection doesn't ship a chainable `.adding(page:)` — small extension
  // so the test factory above reads cleanly. The selection's actual content
  // doesn't matter for these tests; we only need distinct PDFSelection objects.
  private extension PDFSelection {
      func adding(page: PDFPage) -> PDFSelection { self }
  }
  ```

- [ ] **Step 2: Run, see failure**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner/DocumentScanner
  xcodebuild test -scheme DocumentScanner -destination 'id=B762C669-0A64-4665-8C00-10BD6628CBA2' -only-testing:DocumentScannerTests/SearchHighlightTests 2>&1 | tail -10
  ```

- [ ] **Step 3: Implement `SearchHighlight`**

  ```swift
  import Foundation
  import Observation
  import PDFKit

  /// Tracks the current match in a fixed list of PDFSelections. `next()` and
  /// `previous()` wrap. Pure value-type-ish — PDFKit's findString runs once
  /// when the helper is constructed; this class only manages the index.
  @MainActor
  @Observable
  final class SearchHighlight {

      let matches: [PDFSelection]
      private(set) var currentIndex: Int?

      init(matches: [PDFSelection]) {
          self.matches = matches
          self.currentIndex = matches.isEmpty ? nil : 0
      }

      var matchCount: Int { matches.count }

      var current: PDFSelection? {
          guard let i = currentIndex else { return nil }
          return matches[i]
      }

      func next() {
          guard !matches.isEmpty, let i = currentIndex else { return }
          currentIndex = (i + 1) % matches.count
      }

      func previous() {
          guard !matches.isEmpty, let i = currentIndex else { return }
          currentIndex = (i - 1 + matches.count) % matches.count
      }
  }
  ```

- [ ] **Step 4: Tests pass**

  All 7 tests must pass.

- [ ] **Step 5: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/Viewer/SearchHighlight.swift DocumentScanner/DocumentScannerTests/SearchHighlightTests.swift
  git commit -m "Add SearchHighlight: state machine for match index + wrap

  Task 1 of plan-2c: small @Observable class tracking a list of
  PDFSelections and the current index. next() and previous() wrap
  at the ends. Doesn't run findString itself — the viewer hands it
  a pre-computed match list at construction time.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 2: Wire searchTerm through LibraryView → DocumentViewerView

**Files:**
- Modify: `DocumentScanner/DocumentScanner/Library/LibraryView.swift`
- Modify: `DocumentScanner/DocumentScanner/Viewer/DocumentViewerView.swift`

Pass the library's current `searchText` (when non-empty) to the viewer. The viewer accepts it but doesn't use it yet — that's Task 3.

- [ ] **Step 1: Add `searchTerm` property to `DocumentViewerView`**

  In `DocumentViewerView`, add near the other `let` properties:

  ```swift
  let searchTerm: String?
  ```

- [ ] **Step 2: Pass from `LibraryView`'s navigation destination**

  In `LibraryView`'s `.navigationDestination(for: DocumentSummary.self)` closure, find the `DocumentViewerView(...)` call and add `searchTerm:`:

  ```swift
  DocumentViewerView(
      summary: summary,
      storage: storage,
      scannerPresenter: scannerPresenter,
      pipeline: pipeline,
      searchTerm: searchText.isEmpty ? nil : searchText,
      lockSettings: nil,    // do NOT add — lockSettings stays in LibraryView
      onDeleted: { ... }
  )
  ```

  Adjust the existing call site — only add `searchTerm:` matching `String?` between the existing properties. Don't introduce new properties not in this prompt.

- [ ] **Step 3: Build**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner/DocumentScanner
  xcodebuild build -scheme DocumentScanner -destination 'id=B762C669-0A64-4665-8C00-10BD6628CBA2' 2>&1 | grep -E "warning:|error:|BUILD (SUCCEEDED|FAILED)" | grep -v "^ld:\|appintentsmetadataprocessor" | head -10
  ```

  Expected: `** BUILD SUCCEEDED **`. The `searchTerm` is unused at this point — Task 3 wires it.

- [ ] **Step 4: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/Library/LibraryView.swift DocumentScanner/DocumentScanner/Viewer/DocumentViewerView.swift
  git commit -m "Plumb library searchTerm to DocumentViewerView

  Task 2 of plan-2c: add optional searchTerm parameter to the
  viewer and forward LibraryView's current searchText (nil when
  empty). The viewer doesn't use it yet — wired in Task 3.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 3: Highlight matches + prev/next in the bottom toolbar

**Files:**
- Modify: `DocumentScanner/DocumentScanner/Viewer/DocumentViewerView.swift`

When `searchTerm` is non-nil, run `PDFDocument.findString` on the session's PDF, build a `SearchHighlight`, set `PDFView.highlightedSelections` to all matches, and scroll to/focus the current one. Add prev/next buttons and a "N of M" counter to the bottom toolbar (only when matches exist).

The `PDFKitView` wrapper needs to surface its `PDFView` so we can call `setCurrentSelection` and `go(to:)`. We'll do this via a `Coordinator` that captures the view and exposes it through an observable bridge.

- [ ] **Step 1: Update `PDFKitView` to expose the underlying PDFView**

  Find the existing `private struct PDFKitView: UIViewRepresentable` near the bottom of `DocumentViewerView.swift`. Replace it with:

  ```swift
  private struct PDFKitView: UIViewRepresentable {
      let document: PDFDocument
      let highlightedSelections: [PDFSelection]
      let currentSelection: PDFSelection?

      func makeUIView(context: Context) -> PDFView {
          let v = PDFView()
          v.autoScales = true
          v.displayMode = .singlePageContinuous
          v.usePageViewController(false)
          return v
      }

      func updateUIView(_ view: PDFView, context: Context) {
          if view.document !== document {
              view.document = document
          }
          view.highlightedSelections = highlightedSelections.isEmpty ? nil : highlightedSelections
          if let currentSelection {
              view.setCurrentSelection(currentSelection, animate: false)
              view.go(to: currentSelection)
          }
      }
  }
  ```

- [ ] **Step 2: Add `searchHighlight` state and bottom-bar controls to `DocumentViewerView`**

  In the struct, add near the other `@State`:

  ```swift
  @State private var searchHighlight: SearchHighlight?
  ```

  Replace the `PDFKitView(document: session.pdf)` call in `loadedBody` with:

  ```swift
  PDFKitView(
      document: session.pdf,
      highlightedSelections: searchHighlight?.matches ?? [],
      currentSelection: searchHighlight?.current
  )
  ```

  After `.ignoresSafeArea(edges: editMode ? [] : .bottom)` (same level — chain modifier), add:

  ```swift
  .task(id: session.pdf) {
      rebuildHighlight()
  }
  ```

  Add a helper method on the struct:

  ```swift
  private func rebuildHighlight() {
      guard let session, let term = searchTerm, !term.isEmpty else {
          searchHighlight = nil
          return
      }
      let matches = session.pdf.findString(term, withOptions: .caseInsensitive)
      searchHighlight = SearchHighlight(matches: matches)
  }
  ```

  Now augment the bottom toolbar. In the existing `ToolbarItemGroup(placement: .bottomBar)` block, insert AFTER `Spacer()` and BEFORE `ShareLink(...)`:

  ```swift
  if let h = searchHighlight, h.matchCount > 0 {
      Button { h.previous() } label: { Image(systemName: "chevron.up") }
      Text("\((h.currentIndex ?? 0) + 1) of \(h.matchCount)")
          .font(.footnote.monospacedDigit())
          .foregroundStyle(.secondary)
      Button { h.next() } label: { Image(systemName: "chevron.down") }
      Spacer()
  }
  ```

- [ ] **Step 3: Build**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner/DocumentScanner
  xcodebuild build -scheme DocumentScanner -destination 'id=B762C669-0A64-4665-8C00-10BD6628CBA2' 2>&1 | grep -E "warning:|error:|BUILD (SUCCEEDED|FAILED)" | grep -v "^ld:\|appintentsmetadataprocessor" | head -10
  ```

  Expected: `** BUILD SUCCEEDED **`. If you get a warning about `searchHighlight` not being `@Bindable` or `Observable`-compatible inside the `if let h = ...` shadow, try `@Bindable` on the inner usage or restructure to avoid shadowing.

- [ ] **Step 4: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/Viewer/DocumentViewerView.swift
  git commit -m "Highlight search matches + prev/next in viewer bottom bar

  Task 3 of plan-2c: when searchTerm is non-nil, run PDFDocument
  findString on the session's PDF, build a SearchHighlight, and set
  PDFView.highlightedSelections to render every match in yellow.
  The current match is set via setCurrentSelection + go(to:) for
  blue selection overlay + scroll-into-view. Bottom toolbar gains
  chevron.up / chevron.down + a 'N of M' counter when matches
  exist.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 4: Device smoke test

- [ ] **Step 1: Cmd+R to iPhone**

- [ ] **Step 2: Test the happy path**

  - In the library, search for a term you know appears in at least one document (e.g., a name, a number).
  - Tap a result.
  - Viewer opens; the document scrolls to the first match; the match has a blue selection overlay; all other matches show as yellow highlights.
  - Bottom toolbar shows "1 of N" with chevron.up and chevron.down.

- [ ] **Step 3: Test prev/next + wrap**

  - Tap chevron.down: counter advances to "2 of N"; PDF scrolls to the next match; previous match loses the blue overlay (still yellow).
  - Tap chevron.up: counter goes back. At "1 of N", tap up again — wraps to "N of N".
  - At "N of N", tap down → wraps to "1 of N".

- [ ] **Step 4: Test no-search case**

  - Back to library. Clear the search field.
  - Tap any document.
  - Viewer opens with no highlights; bottom toolbar has NO chevrons / counter — just Edit, Share, •••.

- [ ] **Step 5: Test no-matches case**

  - In library, search for something that filters down the list to docs that contain it. Pick one whose match was in the *title* (not content) — e.g. search for a word that's part of the document name only.
  - Tap into that document.
  - The PDF opens without yellow highlights (the term wasn't in the OCR text), and the bottom toolbar doesn't show chevrons.

- [ ] **Step 6: Sanity — nothing else regresses**

  - Open a doc without search context: viewer + edit mode + per-page editor still work.
  - App Lock still works.
  - Privacy blur still triggers on background.

- [ ] **Step 7: Commit milestone**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git commit --allow-empty -m "Milestone: Plan 2c verified end-to-end on device"
  ```

---

## After Plan 2c

What lands:

- Library search term passes through to the viewer.
- All matches highlighted in yellow; current match in blue.
- Bottom-bar prev/next + counter.

What remains:

- **Plan 4** — error edge cases (iCloud unavailable, NSFileVersion conflicts, corrupt PDFs, storage full).
- **Plan 5** — XCUITest golden-path tests.

## Self-review notes

- Scope: tightly bounded — one new helper class, one navigation parameter, additive bottom-toolbar items.
- Type consistency: `searchTerm: String?` matches between LibraryView call site and DocumentViewerView property. `SearchHighlight` API matches in the viewer's `rebuildHighlight()` and bottom-bar usage.
- Placeholder scan: none.
- Test coverage: 7 unit tests for SearchHighlight's index logic. PDFKit search behavior + UI rendering verified via device smoke test.
- Risk: `PDFView.go(to: PDFSelection)` may animate by default; the `updateUIView` will scroll on every selection change. If this becomes jarring, pass `animate: false` to all PDFView calls. Currently `setCurrentSelection` already passes `animate: false`.
